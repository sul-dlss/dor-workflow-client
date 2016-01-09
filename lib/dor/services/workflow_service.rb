require 'rest-client'
require 'active_support'
require 'active_support/core_ext'
require 'nokogiri'
require 'retries'
require 'faraday'
require 'net/http/persistent'

module Dor
  # Create and update workflows
  # yeah, it's big.  it was like that when I got here.  quit nagging me.
  # rubocop:disable Metrics/ClassLength
  class WorkflowService
    attr_accessor :handler, :logger, :resource, :dor_services_url, :valid_statuses, :exceptions_to_catch
    attr_accessor :http_conn

    # Initialize the workflow service
    # @param [String, Faraday, RestClient::Resource] url or configured Faraday/RestClient::Resource object that points to the workflow service
    # @param [Hash] opts optional params
    # @option opts [String]  :dor_services_url uri to the DOR REST service
    # @option opts [Logger]  :logger defaults writing to workflow_service.log with weekly rotation
    # @option opts [Integer] :timeout number of seconds for Faraday timeout, default: 180
    # @option opts [Proc]    :handler code triggered by Faraday exception, receives the exception object, attempt_number and total_delay.  See retries gem.
    # @option opts [Array<Class>] :exceptions_to_catch classes of exceptions to be caught by retry handler
    #
    # TODO: convert RestClient use to Faraday
    def initialize(url, opts = {}) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      params = { :timeout => opts[:timeout] || 3 * 60 }
      @valid_statuses      = opts[:valid_statuses] || %w{waiting completed error queued skipped hold} # From Workflow Service's admin/Process.java
      @dor_services_url    = opts[:dor_services_url] if opts[:dor_services_url]
      @exceptions_to_catch = opts[:exceptions_to_catch] ? Array(opts[:exceptions_to_catch]) : [Faraday::Error]
      @logger              = opts[:logger]  || Logger.new('workflow_service.log', 'weekly')
      @handler             = opts[:handler] || proc do |exception, attempt_number, total_delay|
        @logger.warn "[Attempt #{attempt_number}] #{exception.class}: #{exception.message}; #{total_delay} seconds elapsed."
      end
      url_string = url.is_a?(RestClient::Resource) ? url.url :
                   url.is_a?(Faraday) ? url.url_prefix.to_s : url
      @resource = url.is_a?(RestClient::Resource) ? url : RestClient::Resource.new(url_string, params)
      @http_conn = url.is_a?(Faraday) ? url : Faraday.new(url: url_string) do |faraday|
        faraday.response :logger, @logger if opts[:debug]
        faraday.adapter  :net_http_persistent    # use Keep-Alive connections
      end
    end

    # Creates a workflow for a given object in the repository.  If this particular workflow for this objects exists,
    # it will replace the old workflow with wf_xml passed to this method.  You have the option of creating a datastream or not.
    # Returns true on success.  Caller must handle any exceptions
    #
    # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr"
    # @param [String] druid The id of the object
    # @param [String] workflow_name The name of the workflow you want to create
    # @param [String, Nokogiri::XML::Document] wf_xml The xml that represents the workflow
    # @param [Hash] opts optional params
    # @option opts [Boolean] :create_ds Set to false if you do not want a workflows datastream to be created in Fedora.  Default: true
    # @option opts [String] :lane_id adds laneId attribute to all process elements in the wf_xml workflow xml.  Default: 'default'
    # @return []
    def create_workflow(repo, druid, workflow_name, wf_xml, opts = {:create_ds => true})
      lane_id = opts.fetch(:lane_id, 'default')
      ng_xml = wf_xml.is_a?(Nokogiri::XML::Document) ? wf_xml : Nokogiri::XML(wf_xml)
      ng_xml.xpath('/workflow/process').each { |proc| proc['laneId'] = lane_id }
      workflow_resource_method "#{repo}/objects/#{druid}/workflows/#{workflow_name}", 'put', ng_xml.to_s, {
        :content_type => 'application/xml',
        :params       => { 'create-ds' => opts[:create_ds] }
      }
    end

    # Updates the status of one step in a workflow.  Caller must handle any exceptions.
    # Http Call
    # ==
    # The method does an HTTP PUT to the URL defined in `Dor::WF_URI`.  As an example:
    #     PUT "/dor/objects/pid:123/workflows/GoogleScannedWF/convert"
    #     <process name=\"convert\" status=\"completed\" />"
    # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr"
    # @param [String] druid The id of the object
    # @param [String] workflow The name of the workflow
    # @param [String] process The name of the process step
    # @param [String] status The status that you want to set -- using one of the values in @valid_statuses
    # @param [Hash] opts optional values for the workflow step
    # @option opts [Float] :elapsed The number of seconds it took to complete this step. Can have a decimal.  Is set to 0 if not passed in.
    # @option opts [String] :lifecycle Bookeeping label for this particular workflow step.  Examples are: 'registered', 'shelved'
    # @option opts [String] :note Any kind of string annotation that you want to attach to the workflow
    # @option opts [String] :lane_id Id of processing lane used by the job manager.  Can convey priority or name of an applicaiton specific processing lane (e.g. 'high', 'critical', 'hydrus')
    # @option opts [String] :current_status Setting this string tells the workflow service to compare the current status to this value.  If the current value does not match this value, the update is not performed
    # @return []
    def update_workflow_status(repo, druid, workflow, process, status, opts = {})
      raise ArgumentError, "Unknown status value #{status}" unless @valid_statuses.include?(status.downcase)
      opts = { :elapsed => 0, :lifecycle => nil, :note => nil }.merge!(opts)
      opts[:elapsed] = opts[:elapsed].to_s
      current_status = opts.delete(:current_status)
      xml = create_process_xml({ :name => process, :status => status.downcase }.merge!(opts))
      uri = "#{repo}/objects/#{druid}/workflows/#{workflow}/#{process}"
      uri << "?current-status=#{current_status.downcase}" if current_status
      workflow_resource_method(uri, 'put', xml, { :content_type => 'application/xml' })
    end

    # Retrieves the process status of the given workflow for the given object identifier
    # @param [String] repo The repository the object resides in.  Currently recoginzes "dor" and "sdr".
    # @param [String] druid The id of the object
    # @param [String] workflow The name of the workflow
    # @param [String] process The name of the process step
    # @return [String] status for repo-workflow-process-druid
    def get_workflow_status(repo, druid, workflow, process)
      doc = get_workflow_ngxml(repo, druid, workflow)
      status = doc.root.at_xpath("//process[@name='#{process}']/@status")
      status = status.content if status
      status
    end

    #
    # Retrieves the raw XML for the given workflow
    # @param [String] repo The repository the object resides in.  Currently recoginzes "dor" and "sdr".
    # @param [String] druid The id of the object
    # @param [String] workflow The name of the workflow
    # @return [String] XML of the workflow
    def get_workflow_xml(repo, druid, workflow)
      workflow_resource_method "#{repo}/objects/#{druid}/workflows/#{workflow}"
    end

    # Same as get_workflow_xml, but returns Nokogiri::XML object
    # @see get_workflow_xml
    # @return [Nokogiri::XML] document
    def get_workflow_ngxml(repo, druid, workflow)
      xml = get_workflow_xml(repo, druid, workflow)
      doc = Nokogiri::XML(xml)
      if doc.root.nil?
        @logger.warn("Unable to parse response:\n #{xml}")
        raise Exception.new("Unable to parse response:\n #{xml}")
      end
      doc
    end

    # Get workflow names into an array for given PID
    # This method only works when this gem is used in a project that is configured to connect to DOR
    #
    # @param [String] pid of druid
    # @param [String] repo repository for the object
    # @return [Array<String>] list of worklows
    # @example
    #   dwfs = Dor::WorkflowService.new('http://sul-lyberservices-dev.stanford.edu/workflow')
    #   dwfs.get_workflows('druid:sr100hp0609')
    #   => ["accessionWF", "assemblyWF", "disseminationWF"]
    def get_workflows(pid, repo = 'dor')
      get_workflow_ngxml(repo, pid, '').xpath('//workflow').collect {|workflow| workflow['id']}
    end

    # Get active workflow names into an array for given PID
    # This method only works when this gem is used in a project that is configured to connect to DOR
    #
    # @param [String] repo repository of the object
    # @param [String] pid id of object
    # @return [Array<String>] list of active worklows.  Returns an empty Array if none are found
    # @example
    #   Dor::WorkflowService.get_workflows('dor', 'druid:sr100hp0609')
    #   => ["accessionWF", "assemblyWF", "disseminationWF"]
    def get_active_workflows(repo, pid)
      get_workflow_ngxml(repo, pid, '').xpath('//workflow[not(process/@archived)]/@id').map(&:value)
    end

    # Updates the status of one step in a workflow to error.  Caller must handle any exceptions
    #
    # HTTP Call
    # ==
    # The method does an HTTP PUT to the URL defined in `Dor::WF_URI`.
    #
    #     PUT "/dor/objects/pid:123/workflows/GoogleScannedWF/convert"
    #     <process name=\"convert\" status=\"error\" />"
    #
    # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr"
    # @param [String] druid The id of the object
    # @param [String] workflow The name of the workflow
    # @param [String] error_msg The error message.  Ideally, this is a brief message describing the error
    # @param [Hash] opts optional values for the workflow step
    # @option opts [String] :error_text A slot to hold more information about the error, like a full stacktrace
    # @return []
    def update_workflow_error_status(repo, druid, workflow, process, error_msg, opts = {})
      opts = {:error_text => nil}.merge!(opts)
      xml = create_process_xml({:name => process, :status => 'error', :errorMessage => error_msg}.merge!(opts))
      workflow_resource_method "#{repo}/objects/#{druid}/workflows/#{workflow}/#{process}", 'put', xml, {:content_type => 'application/xml'}
    end

    # Deletes a workflow from a particular repository and druid
    # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr"
    # @param [String] druid The id of the object to delete the workflow from
    # @param [String] workflow The name of the workflow to be deleted
    # @return []
    def delete_workflow(repo, druid, workflow)
      workflow_resource_method "#{repo}/objects/#{druid}/workflows/#{workflow}", 'delete'
    end

    # Returns the Date for a requested milestone from workflow lifecycle
    # @param [String] repo repository name
    # @param [String] druid object id
    # @param [String] milestone name of the milestone being queried for
    # @param [Boolean] active_only limit to active workflows
    # @return [Time] when the milestone was achieved.  Returns nil if the milestone does not exist
    # @example An example lifecycle xml from the workflow service.
    #   <lifecycle objectId="druid:ct011cv6501">
    #     <milestone date="2010-04-27T11:34:17-0700">registered</milestone>
    #     <milestone date="2010-04-29T10:12:51-0700">inprocess</milestone>
    #     <milestone date="2010-06-15T16:08:58-0700">released</milestone>
    #   </lifecycle>
    def get_lifecycle(repo, druid, milestone, active_only = false)
      doc = query_lifecycle(repo, druid, active_only)
      milestone = doc.at_xpath("//lifecycle/milestone[text() = '#{milestone}']")
      return nil unless milestone
      Time.parse(milestone['date'])
    end

    # Returns the Date for a requested milestone ONLY FROM THE ACTIVE workflow table
    # @see get_lifecycle
    def get_active_lifecycle(repo, druid, milestone)
      get_lifecycle(repo, druid, milestone, true)
    end

    # @return [Hash]
    def get_milestones(repo, druid)
      doc = query_lifecycle(repo, druid)
      doc.xpath('//lifecycle/milestone').collect do |node|
        { :milestone => node.text, :at => Time.parse(node['date']), :version => node['version'] }
      end
    end

    # Converts repo-workflow-step into repo:workflow:step
    # @param [String] default_repository
    # @param [String] default_workflow
    # @param [String] step if contains colon :, then the value for workflow and/or workflow/repository. For example: 'jp2-create', 'assemblyWF:jp2-create' or 'dor:assemblyWF:jp2-create'
    # @return [String] repo:workflow:step
    # @example
    #   dor:assemblyWF:jp2-create
    def qualify_step(default_repository, default_workflow, step)
      current = step.split(/:/, 3)
      current.unshift(default_workflow)   if current.length < 3
      current.unshift(default_repository) if current.length < 3
      current.join(':')
    end

    # Returns a list of druids from the WorkflowService that match the criteria of the completed and waiting params
    #
    # @param [Array<String>, String] completed An array or single String of the completed steps, should use the qualified format: `repository:workflow:step-name`
    # @param [String] waiting name of the waiting step
    # @param [String] repository default repository to use if it isn't passed in the qualified-step-name
    # @param [String] workflow default workflow to use if it isn't passed in the qualified-step-name
    # @param [String] lane_id issue a query for a specific lane_id for the waiting step
    # @param [Hash] options
    # @option options [String]  :default_repository repository to query for if not using the qualified format
    # @option options [String]  :default_workflow workflow to query for if not using the qualified format
    # @option options [Integer] :limit maximum number of druids to return (nil for no limit)
    # @return [Array<String>] Array of druids
    #
    # @example
    #     dwfs.get_objects_for_workstep(...)
    #     => [ 'druid:py156ps0477', 'druid:tt628cb6479', 'druid:ct021wp7863' ]
    # @example
    #     dwfs.get_objects_for_workstep(..., 'lane1')
    #     => [ 'druid:py156ps0477', 'druid:tt628cb6479' ]
    # @example
    #     dwfs.get_objects_for_workstep(..., 'lane1', limit: 1)
    #     => [ 'druid:py156ps0477' ]
    #
    def get_objects_for_workstep(completed, waiting, lane_id = 'default', options = {})
      waiting_param = qualify_step(options[:default_repository], options[:default_workflow], waiting)
      uri_string = "workflow_queue?waiting=#{waiting_param}"
      if completed
        Array(completed).each do |step|
          completed_param = qualify_step(options[:default_repository], options[:default_workflow], step)
          uri_string << "&completed=#{completed_param}"
        end
      end

      uri_string << "&limit=#{options[:limit].to_i}" if options[:limit] && options[:limit].to_i > 0
      uri_string << "&lane-id=#{lane_id}"
      resp = workflow_resource_method uri_string
      #
      # response looks like:
      #    <objects count="2">
      #      <object id="druid:ab123de4567"/>
      #      <object id="druid:ab123de9012"/>
      #    </objects>
      #
      # convert into:
      #   ['druid:ab123de4567', 'druid:ab123de9012']
      #
      Nokogiri::XML(resp).xpath('//object[@id]').map { |n| n[:id] }
    end

    # Get a list of druids that have errored out in a particular workflow and step
    # @param [String] workflow name
    # @param [String] step name
    # @param [String] repository
    # @return [Hash] hash of results, with key has a druid, and value as the error message
    # @example
    #     Dor::WorkflowService.get_errored_objects_for_workstep('accessionWF','content-metadata')
    #     => {"druid:qd556jq0580"=>"druid:qd556jq0580 - Item error; caused by
    #        #<Rubydora::FedoraInvalidRequest: Error modifying datastream contentMetadata for druid:qd556jq0580. See logger for details>"}
    def get_errored_objects_for_workstep(workflow, step, repository = 'dor')
      resp = workflow_resource_method "workflow_queue?repository=#{repository}&workflow=#{workflow}&error=#{step}"
      result = {}
      Nokogiri::XML(resp).xpath('//object').collect do |node|
        result.merge!(node['id'] => node['errorMessage'])
      end
      result
    end

    # Returns the number of objects that have a status of 'error' in a particular workflow and step
    # @param [String] workflow name
    # @param [String] step name
    # @param [String] repository
    # @return [Integer] Number of objects with this repository:workflow:step that have a status of 'error'
    def count_errored_for_workstep(workflow, step, repository = 'dor')
      count_objects_in_step(workflow, step, repository, 'error')
    end

    # Returns the number of objects that have a status of 'queued' in a particular workflow and step
    # @param [String] workflow name
    # @param [String] step name
    # @param [String] repository
    # @return [Integer] Number of objects with this repository:workflow:step that have a status of 'queued'
    def count_queued_for_workstep(workflow, step, repository = 'dor')
      count_objects_in_step(workflow, step, repository, 'queued')
    end

    # Gets all of the workflow steps that have a status of 'queued' that have a last-updated timestamp older than the number of hours passed in
    #   This will enable re-queueing of jobs that have been lost by the job manager
    # @param [String] repository name of the repository you want to query, like 'dor' or 'sdr'
    # @param [Hash] opts optional values for query
    # @option opts [Integer] :hours_ago steps older than this value will be returned by the query.  The service defaults to 0 hours, meaning you will get all queued workflows
    # @option opts [Integer] :limit maximum number of workflow steps to return.  Default: unlimited.
    # @return [Array[Hash]] each Hash represents a workflow step, including the following keys: :workflow, :step, :druid, :lane_id
    def get_stale_queued_workflows(repository, opts = {})
      uri_string = build_queued_uri(repository, opts)
      parse_queued_workflows_response workflow_resource_method(uri_string)
    end

    # Returns a count of workflow steps that have a status of 'queued' that have a last-updated timestamp older than the number of hours passed in
    # @param [String] repository name of the repository you want to query, like 'dor' or 'sdr'
    # @param [Hash] opts optional values for query
    # @option opts [Integer] :hours_ago steps older than this value will be returned by the query.  The service defaults to 0 hours, meaning you will get all queued workflows
    # @return [Integer] number of stale queued steps
    def count_stale_queued_workflows(repository, opts = {})
      uri_string = build_queued_uri(repository, opts) + '&count-only=true'
      doc = Nokogiri::XML(workflow_resource_method uri_string)
      doc.at_xpath('/objects/@count').value.to_i
    end

    # @param [Hash] params
    # @return [String] XML
    def create_process_xml(params)
      builder = Nokogiri::XML::Builder.new do |xml|
        attrs = params.reject { |_k, v| v.nil? }
        attrs = Hash[ attrs.map {|k, v| [k.to_s.camelize(:lower), v]}] # camelize all the keys in the attrs hash
        xml.process(attrs)
      end
      builder.to_xml
    end

    # @return [Nokogiri::XML::Document]
    def query_lifecycle(repo, druid, active_only = false)
      req = "#{repo}/objects/#{druid}/lifecycle"
      req << '?active-only=true' if active_only
      Nokogiri::XML(workflow_resource_method req)
    end

    # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr"
    # @param [String] druid The id of the object to archive the workflows from
    def archive_active_workflow(repo, druid)
      get_active_workflows(repo, druid).each { |wf| archive_workflow(druid, wf) }
    end

    # @param [String] druid The id of the object to delete the workflow from
    # @param [String] wf_name Workflow name
    # @param [Integer] version_num Version number to be posted
    def archive_workflow(druid, wf_name, version_num = nil)
      raise 'Initialization like Dor::WorkflowService.new(workflow_service_url, :dor_services_url => DOR_SERVIES_URL) required before archiving workflow' if @dor_services_url.nil?
      dor_services = RestClient::Resource.new(@dor_services_url)
      url = "/v1/objects/#{druid}/workflows/#{wf_name}/archive"
      url << "/#{version_num}" if version_num
      dor_services[url].post ''
    end

    # Calls the versionClose endpoint of the WorkflowService:
    #  - completes the versioningWF:submit-version and versioningWF:start-accession steps
    #  - initiates accesssionWF
    # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr"
    # @param [String] druid The id of the object to delete the workflow from
    # @param [Boolean] create_accession_wf Option to create accessionWF when closing a version
    def close_version(repo, druid, create_accession_wf = true)
      uri = "#{repo}/objects/#{druid}/versionClose"
      uri << '?create-accession=false' unless create_accession_wf
      workflow_resource_method(uri, 'post', '')
    end

    # Returns all the distinct laneIds for a given workflow step
    # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr"
    # @param [String] workflow name
    # @param [String] process name
    # @return [Array<String>] all of the distinct laneIds.  Array will be empty if no lane ids were found
    def get_lane_ids(repo, workflow, process)
      uri = "workflow_queue/lane_ids?step=#{repo}:#{workflow}:#{process}"
      doc = Nokogiri::XML(workflow_resource_method uri)
      doc.xpath('/lanes/lane').map { |n| n['id'] }
    end

    protected

    def build_queued_uri(repository, opts = {})
      uri_string = "workflow_queue/all_queued?repository=#{repository}"
      uri_string << "&hours-ago=#{opts[:hours_ago]}" if opts[:hours_ago]
      uri_string << "&limit=#{opts[:limit]}"         if opts[:limit]
      uri_string
    end

    def parse_queued_workflows_response(xml)
      doc = Nokogiri::XML(xml)
      doc.xpath('/workflows/workflow').collect do |wf_node|
        {
          :workflow => wf_node['name'],
          :step     => wf_node['process'],
          :druid    => wf_node['druid'],
          :lane_id  => wf_node['laneId']
        }
      end
    end

    def count_objects_in_step(workflow, step, type, repo)
      resp = workflow_resource_method "workflow_queue?repository=#{repo}&workflow=#{workflow}&#{type}=#{step}"
      node = Nokogiri::XML(resp).at_xpath('/objects')
      raise 'Unable to determine count from response' if node.nil?
      node['count'].to_i
    end

    # Calls @resource[uri_string]."#{meth}" with variable number of optional arguments
    # The point of this is to wrap ALL remote calls with consistent error handling and logging
    # @param [String] uri_string resource to request
    # @param [String] meth REST method to use on resource (get, put, post, delete, etc.)
    # @param [String] payload body for (e.g. put) request
    # @param [Hash] opts addtional headers options
    # @return [Object] response from method
    def workflow_resource_method(uri_string, meth = 'get', payload = '', opts = {})
      with_retries(:max_tries => 2, :handler => @handler, :rescue => @exceptions_to_catch) do |attempt|
        @logger.info "[Attempt #{attempt}] #{meth} #{@resource.url}/#{uri_string}"
        if meth == 'get'
          fail NotImplementedError, "GET does not support extra headers: #{opts}" unless opts.length == 0
          @logger.debug "Persistent HTTP GET #{uri_string} (#{@http_conn.inspect})"
          @http_conn.get(uri_string).body
        elsif meth == 'delete'
          @resource[uri_string].send(meth, opts)
        elsif opts.size == 0 # right number of args allows existing test expect/with statements to continue working
          @resource[uri_string].send(meth, payload)
        else
          @resource[uri_string].send(meth, payload, opts)
        end
      end
    end

  end
end
