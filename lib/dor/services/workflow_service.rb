require 'active_support'
require 'active_support/core_ext'
require 'nokogiri'
require 'retries'
require 'faraday'

module Dor

  # TODO: major version revision: change pattern of usage to be normal non-singleton class
  # TODO: convert @@class_vars to regular attributes
  # TODO: create normal initalize method, deprecate configure
  # TODO: hardcoded 'true' returns are dumb, instead return the response object where possible
  # TODO: VALID_STATUS should be just another attribute w/ default
  # TODO: allow constructor/initalizer to receive Faraday object(s), not just URLs (solves SSL/proxy config problem)
  # TODO: allow constructor/initalizer to receive logger

  # Create and update workflows
  class WorkflowService
    class << self

      @@handler  = nil
      @@logger   = nil
      @@resource = nil
      @@dor_services_url = nil
      @@http_conn = nil

      # From Workflow Service's admin/Process.java
      VALID_STATUS = %w{waiting completed error queued skipped hold}

      # Creates a workflow for a given object in the repository.  If this particular workflow for this objects exists,
      # it will replace the old workflow with wf_xml passed to this method.  You have the option of creating a datastream or not.
      # Returns true on success.  Caller must handle any exceptions
      #
      # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
      # @param [String] druid The id of the object
      # @param [String] workflow_name The name of the workflow you want to create
      # @param [String] wf_xml The xml that represents the workflow
      # @param [Hash] opts optional params
      # @option opts [Boolean] :create_ds if true, a workflow datastream will be created in Fedora.  Set to false if you do not want a datastream to be created
      #   If you do not pass in an <b>opts</b> Hash, then :create_ds is set to true by default
      # @option opts [String] :lane_id adds laneId attribute to all process elements in the wf_xml workflow xml.  Defaults to a value of 'default'
      # @return [Boolean] always true
      #
      def create_workflow(repo, druid, workflow_name, wf_xml, opts = {:create_ds => true})
        lane_id = opts.fetch(:lane_id, 'default')
        xml = add_lane_id_to_workflow_xml(lane_id, wf_xml)
        status = workflow_resource_method "#{repo}/objects/#{druid}/workflows/#{workflow_name}", 'put', xml,
          {
            :content_type => 'application/xml',
            :params       => { 'create-ds' => opts[:create_ds] }
          }
        true
      end

      # Updates the status of one step in a workflow.
      # Returns true on success.  Caller must handle any exceptions
      #
      # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
      # @param [String] druid The id of the object
      # @param [String] workflow The name of the workflow
      # @param [String] process The name of the process step
      # @param [String] status The status that you want to set -- using one of the values in VALID_STATUS
      # @param [Hash] opts optional values for the workflow step
      # @option opts [Float] :elapsed The number of seconds it took to complete this step. Can have a decimal.  Is set to 0 if not passed in.
      # @option opts [String] :lifecycle Bookeeping label for this particular workflow step.  Examples are: 'registered', 'shelved'
      # @option opts [String] :note Any kind of string annotation that you want to attach to the workflow
      # @option opts [String] :lane_id Id of processing lane used by the job manager.  Can convey priority or name of an applicaiton specific processing lane (e.g. 'high', 'critical', 'hydrus')
      # @option opts [String] :current_status Setting this string tells the workflow service to compare the current status to this value.  If the current value does not match this value, the update is not performed
      # @return [Boolean] always true
      # Http Call
      # ==
      # The method does an HTTP PUT to the URL defined in `Dor::WF_URI`.  As an example:
      #
      #     PUT "/dor/objects/pid:123/workflows/GoogleScannedWF/convert"
      #     <process name=\"convert\" status=\"completed\" />"
      def update_workflow_status(repo, druid, workflow, process, status, opts = {})
        raise ArgumentError, "Unknown status value #{status}" unless VALID_STATUS.include?(status.downcase)
        opts = { :elapsed => 0, :lifecycle => nil, :note => nil }.merge!(opts)
        opts[:elapsed] = opts[:elapsed].to_s
        current_status = opts.delete(:current_status)
        xml = create_process_xml({ :name => process, :status => status.downcase }.merge!(opts))
        uri = "#{repo}/objects/#{druid}/workflows/#{workflow}/#{process}"
        uri << "?current-status=#{current_status.downcase}" if current_status
        workflow_resource_method(uri, 'put', xml, { :content_type => 'application/xml' })
        true
      end

      #
      # Retrieves the process status of the given workflow for the given object identifier
      # @param [String] repo The repository the object resides in.  Currently recoginzes "dor" and "sdr".
      # @param [String] druid The id of the object
      # @param [String] workflow The name of the workflow
      # @param [String] process The name of the process step
      # @return [String] status for repo-workflow-process-druid
      def get_workflow_status(repo, druid, workflow, process)
        workflow_md = get_workflow_xml(repo, druid, workflow)
        doc = Nokogiri::XML(workflow_md)
        raise Exception.new("Unable to parse response:\n#{workflow_md}") if doc.root.nil?
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

      # Get workflow names into an array for given PID
      # This method only works when this gem is used in a project that is configured to connect to DOR
      #
      # @param [String] pid of druid
      # @param [String] repo repository for the object
      # @return [Array<String>] list of worklows
      # @example
      #   Dor::WorkflowService.get_workflows('druid:sr100hp0609')
      #   => ["accessionWF", "assemblyWF", "disseminationWF"]
      def get_workflows(pid, repo = 'dor')
        xml_doc = Nokogiri::XML(get_workflow_xml(repo, pid, ''))
        xml_doc.xpath('//workflow').collect {|workflow| workflow['id']}
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
        doc = Nokogiri::XML(get_workflow_xml(repo, pid, ''))
        doc.xpath( %(//workflow[not(process/@archived)]/@id ) ).map {|n| n.value}
      end

      # Updates the status of one step in a workflow to error.
      # Returns true on success.  Caller must handle any exceptions
      #
      # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
      # @param [String] druid The id of the object
      # @param [String] workflow The name of the workflow
      # @param [String] error_msg The error message.  Ideally, this is a brief message describing the error
      # @param [Hash] opts optional values for the workflow step
      # @option opts [String] :error_text A slot to hold more information about the error, like a full stacktrace
      # @return [Boolean] always true
      #
      # Http Call
      # ==
      # The method does an HTTP PUT to the URL defined in `Dor::WF_URI`.
      #
      #     PUT "/dor/objects/pid:123/workflows/GoogleScannedWF/convert"
      #     <process name=\"convert\" status=\"error\" />"
      def update_workflow_error_status(repo, druid, workflow, process, error_msg, opts = {})
        opts = {:error_text => nil}.merge!(opts)
        xml = create_process_xml({:name => process, :status => 'error', :errorMessage => error_msg}.merge!(opts))
        workflow_resource_method "#{repo}/objects/#{druid}/workflows/#{workflow}/#{process}", 'put', xml, {:content_type => 'application/xml'}
        true
      end

      # Deletes a workflow from a particular repository and druid
      # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
      # @param [String] druid The id of the object to delete the workflow from
      # @param [String] workflow The name of the workflow to be deleted
      # @return [Boolean] always true
      def delete_workflow(repo, druid, workflow)
        workflow_resource_method "#{repo}/objects/#{druid}/workflows/#{workflow}", 'delete'
        true
      end

      # Returns the Date for a requested milestone from workflow lifecycle
      # @param [String] repo repository name
      # @param [String] druid object id
      # @param [String] milestone name of the milestone being queried for
      # @return [Time] when the milestone was achieved.  Returns nil if the milestone does not exist
      # @example An example lifecycle xml from the workflow service.
      #   <lifecycle objectId="druid:ct011cv6501">
      #     <milestone date="2010-04-27T11:34:17-0700">registered</milestone>
      #     <milestone date="2010-04-29T10:12:51-0700">inprocess</milestone>
      #     <milestone date="2010-06-15T16:08:58-0700">released</milestone>
      #   </lifecycle>
      def get_lifecycle(repo, druid, milestone)
        doc = query_lifecycle(repo, druid)
        milestone = doc.at_xpath("//lifecycle/milestone[text() = '#{milestone}']")
        return Time.parse(milestone['date']) if milestone
        nil
      end

      # Returns the Date for a requested milestone ONLY FROM THE ACTIVE workflow table
      # @param [String] repo repository name
      # @param [String] druid object id
      # @param [String] milestone name of the milestone being queried for
      # @return [Time] when the milestone was achieved.  Returns nil if the milestone does not exist
      # @example An example lifecycle xml from the workflow service.
      #   <lifecycle objectId="druid:ct011cv6501">
      #     <milestone date="2010-04-27T11:34:17-0700">registered</milestone>
      #     <milestone date="2010-04-29T10:12:51-0700">inprocess</milestone>
      #     <milestone date="2010-06-15T16:08:58-0700">released</milestone>
      #   </lifecycle>
      def get_active_lifecycle(repo, druid, milestone)
        doc = query_lifecycle(repo, druid, true)
        milestone = doc.at_xpath("//lifecycle/milestone[text() = '#{milestone}']")
        return Time.parse(milestone['date']) if milestone
        nil
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

      # Returns a list of druids from the WorkflowService that meet the criteria of the passed in completed and waiting params
      #
      # @param [Array<String>, String] completed An array or single String of the completed steps, should use the qualified format: `repository:workflow:step-name`
      # @param [String] waiting name of the waiting step
      # @param [String] repository default repository to use if it isn't passed in the qualified-step-name
      # @param [String] workflow default workflow to use if it isn't passed in the qualified-step-name
      # @param [String] lane_id issue a query for a specific lane_id for the waiting step
      # @param [Hash] options
      # @param options  [String]  :default_repository repository to query for if not using the qualified format
      # @param options  [String]  :default_workflow workflow to query for if not using the qualified format
      # @option options [Integer] :limit maximum number of druids to return (nil for no limit)
      # @return [Array<String>]  Array of druids
      #
      # @example
      #     get_objects_for_workstep(...)
      #     => [
      #        "druid:py156ps0477",
      #        "druid:tt628cb6479",
      #        "druid:ct021wp7863"
      #      ]
      #
      # @example
      #     get_objects_for_workstep(..., "lane1")
      #     => {
      #      "druid:py156ps0477",
      #      "druid:tt628cb6479",
      #     }
      #
      # @example
      #     get_objects_for_workstep(..., "lane1", limit: 1)
      #     => {
      #      "druid:py156ps0477",
      #     }
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

        uri_string << "&limit=#{options[:limit].to_i}"  if options[:limit] && options[:limit].to_i > 0
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
        result = Nokogiri::XML(resp).xpath('//object[@id]')
        result.map { |n| n[:id] }
      end

      # Get a list of druids that have errored out in a particular workflow and step
      #
      # @param [String] workflow name
      # @param [String] step name
      # @param [String] repository -- optional, default=dor
      #
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
      #
      # @param [String] workflow name
      # @param [String] step name
      # @param [String] repository -- optional, default=dor
      #
      # @return [Integer] Number of objects with this repository:workflow:step that have a status of 'error'
      def count_errored_for_workstep(workflow, step, repository = 'dor')
        count_objects_in_step(workflow, step, 'error', repository)
      end

      # Returns the number of objects that have a status of 'queued' in a particular workflow and step
      #
      # @param [String] workflow name
      # @param [String] step name
      # @param [String] repository -- optional, default=dor
      #
      # @return [Integer] Number of objects with this repository:workflow:step that have a status of 'queued'
      def count_queued_for_workstep(workflow, step, repository = 'dor')
        count_objects_in_step(workflow, step, 'queued', repository)
      end

      # Gets all of the workflow steps that have a status of 'queued' that have a last-updated timestamp older than the number of hours passed in
      #   This will enable re-queueing of jobs that have been lost by the job manager
      # @param [String] repository name of the repository you want to query, like 'dor' or 'sdr'
      # @param [Hash] opts optional values for query
      # @option opts [Integer] :hours_ago steps older than this value will be returned by the query.  If not passed in, the service defaults to 0 hours,
      #   meaning you will get all queued workflows
      # @option opts [Integer] :limit sets the maximum number of workflow steps that can be returned.  Defaults to no limit
      # @return [Array[Hash]] each Hash represents a workflow step.  It will have the following keys:
      #  :workflow, :step, :druid, :lane_id
      def get_stale_queued_workflows(repository, opts = {})
        uri_string = build_queued_uri(repository, opts)
        parse_queued_workflows_response workflow_resource_method(uri_string)
      end

      # Returns a count of workflow steps that have a status of 'queued' that have a last-updated timestamp older than the number of hours passed in
      # @param [String] repository name of the repository you want to query, like 'dor' or 'sdr'
      # @param [Hash] opts optional values for query
      # @option opts [Integer] :hours_ago steps older than this value will be returned by the query.  If not passed in, the service defaults to 0 hours,
      #   meaning you will get all queued workflows
      # @return [Integer] number of stale, queued steps if the :count_only option was set to true
      def count_stale_queued_workflows(repository, opts = {})
        uri_string = build_queued_uri(repository, opts) + '&count-only=true'
        doc = Nokogiri::XML(workflow_resource_method uri_string)
        doc.at_xpath('/objects/@count').value.to_i
      end

      # @param [Hash] params
      # @return [String]
      def create_process_xml(params)
        builder = Nokogiri::XML::Builder.new do |xml|
          attrs = params.reject { |k, v| v.nil? }
          attrs = Hash[ attrs.map {|k, v| [k.to_s.camelize(:lower), v]}]  # camelize all the keys in the attrs hash
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

      # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
      # @param [String] druid The id of the object to archive the workflows from
      def archive_active_workflow(repo, druid)
        workflows = get_active_workflows(repo, druid)
        workflows.each do |wf|
          archive_workflow(repo, druid, wf)
        end
      end

      # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
      # @param [String] druid The id of the object to delete the workflow from
      def archive_workflow(repo, druid, wf_name, version_num = nil)
        raise 'Please call Dor::WorkflowService.configure(workflow_service_url, :dor_services_url => DOR_SERVIES_URL) once before archiving workflow' if @@dor_services_url.nil?
        url = "/v1/objects/#{druid}/workflows/#{wf_name}/archive"
        url << "/#{version_num}" if version_num
        workflow_resource_method(url, 'post', '')
      end

      # Calls the versionClose endpoint of the WorkflowService:
      #
      # - completes the versioningWF:submit-version and versioningWF:start-accession steps
      # - initiates accesssionWF
      #
      # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
      # @param [String] druid The id of the object to delete the workflow from
      # @param [Boolean] create_accession_wf Option to create accessionWF when closing a version.  Defaults to true
      def close_version(repo, druid, create_accession_wf = true)
        uri = "#{repo}/objects/#{druid}/versionClose"
        uri << '?create-accession=false' unless create_accession_wf
        workflow_resource_method(uri, 'post', '')
        true
      end

      # Returns all the distinct laneIds for a given workflow step
      #
      # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
      # @param [String] workflow name
      # @param [String] process name
      # @return [Array<String>] all of the distinct laneIds.  Array will be empty if no lane ids were found
      def get_lane_ids(repo, workflow, process)
        uri = "workflow_queue/lane_ids?step=#{repo}:#{workflow}:#{process}"
        doc = Nokogiri::XML(workflow_resource_method uri)
        nodes = doc.xpath('/lanes/lane')
        nodes.map { |n| n['id'] }
      end

      ### MIMICKING ATTRIBUTE READER
      # @return [Faraday::Connection] the REST client resource created during configure()
      def workflow_resource
        raise 'Please call Dor::WorkflowService.configure(url) once before calling any WorkflowService methods' if @@http_conn.nil?
        @@http_conn
      end

      # Among other things, a distinct method helps tests mock default logger
      # @param [String, IO] logdev The log device. This is a filename (String) or IO object (typically STDOUT, STDERR, or an open file).
      # @param [String, Integer] shift_age Number of old log files to keep, or frequency of rotation (daily, weekly or monthly).
      # @return [Logger] default logger object
      def default_logger(logdev = 'workflow_service.log', shift_age = 'weekly')
        Logger.new(logdev, shift_age)
      end

      def workflow_service_exceptions_to_catch
        [Faraday::Error]
      end

      # Configure the workflow service
      # TODO: replace with initialize
      # @param [String] url points to the workflow service
      # @param [Hash] opts optional params
      # @option opts [Logger] :logger defaults writing to workflow_service.log with weekly rotation
      # @option opts [String] :dor_services_url uri to the DOR REST service
      # @option opts [Integer] :timeout number of seconds for HTTP timeout
      # @option opts [String] :client_cert_file path to an SSL client certificate (deprecated)
      # @option opts [String] :client_key_file path to an SSL key file (deprecated)
      # @option opts [String] :client_key_pass password for the key file (deprecated)
      # @return [Faraday::Connection] the REST client resource
      def configure(url_or_connection, opts = {})
        @@logger           = opts[:logger] || default_logger
        @@dor_services_url = opts[:dor_services_url] if opts[:dor_services_url]
        # params[:ssl_client_cert] = OpenSSL::X509::Certificate.new(File.read(opts[:client_cert_file])) if opts[:client_cert_file]
        # params[:ssl_client_key]  = OpenSSL::PKey::RSA.new(File.read(opts[:client_key_file]), opts[:client_key_pass]) if opts[:client_key_file]
        @@handler = Proc.new do |exception, attempt_number, total_delay|
          @@logger.warn "[Attempt #{attempt_number}] #{exception.class}: #{exception.message}; #{total_delay} seconds elapsed."
        end
        @@http_conn = case url_or_connection
                      when String
                        Faraday.new(url: url_or_connection) do |faraday|
                          faraday.response :logger if opts[:debug] # logs to STDOUT
                          faraday.adapter  :net_http_persistent    # use Keep-Alive connections
                          faraday.use Faraday::Response::RaiseError
                          if opts.key? :timeout
                            faraday.options.timeout = opts[:timeout]
                            faraday.options.open_timeout = opts[:timeout]
                          end
                        end
                      else
                        url_or_connection
                      end
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

      # Adds laneId attributes to each process of workflow xml
      #
      # @param [String] lane_id to add to each process element
      # @param [String] wf_xml the workflow xml
      # @return [String] wf_xml with lane_id attributes
      def add_lane_id_to_workflow_xml(lane_id, wf_xml)
        doc = Nokogiri::XML(wf_xml)
        doc.xpath('/workflow/process').each { |proc| proc['laneId'] = lane_id }
        doc.to_xml
      end

      def count_objects_in_step(workflow, step, type, repo)
        resp = workflow_resource_method "workflow_queue?repository=#{repo}&workflow=#{workflow}&#{type}=#{step}"
        node = Nokogiri::XML(resp).at_xpath('/objects')
        raise 'Unable to determine count from response' if node.nil?
        node['count'].to_i
      end

      # calls workflow_resource[uri_string]."#{meth}" with variable number of optional arguments
      # The point of this is to wrap ALL remote calls with consistent error handling and logging
      # @param [String] uri_string resource to request
      # @param [String] meth REST method to use on resource (get, put, post, delete, etc.)
      # @param [String] payload body for (e.g. put) request
      # @param [Hash] opts addtional headers options
      # @return [Object] response from method
      def workflow_resource_method(uri_string, meth = 'get', payload = '', opts = {})
        with_retries(:max_tries => 2, :handler => @@handler, :rescue => workflow_service_exceptions_to_catch) do |attempt|
          @@logger.info "[Attempt #{attempt}] #{meth} #{workflow_resource.url_prefix}/#{uri_string}"

          response = workflow_resource.send(meth, uri_string) do |req|
            req.body = payload unless meth == 'delete'

            req.params.update opts[:params] if opts[:params]

            req.headers.update opts.except(:params)
          end

          response.body
        end
      end

    end
  end
end
