require 'rest-client'
require 'active_support/core_ext'
require 'nokogiri'

module Dor

  # Methods to create and update workflow
  module WorkflowService
    class << self

      @@resource = nil
      @@dor_services_url = nil

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
      # @option opts [Integer] :priority adds priority to all process elements in the wf_xml workflow xml
      # @return [Boolean] always true
      #
      def create_workflow(repo, druid, workflow_name, wf_xml, opts = {:create_ds => true})
        xml = wf_xml
        xml = add_priority_to_workflow_xml(opts[:priority], wf_xml) if(opts[:priority])
        workflow_resource["#{repo}/objects/#{druid}/workflows/#{workflow_name}"].put(xml, :content_type => 'application/xml',
                                                                                     :params => {'create-ds' => opts[:create_ds] })
        return true
      end

      # Adds priority attributes to each process of workflow xml
      #
      # @param [Integer] priority value to add to each process element
      # @param [String] wf_xml the workflow xml
      # @return [String] wf_xml with priority attributes
      def add_priority_to_workflow_xml(priority, wf_xml)
        return wf_xml if(priority.to_i == 0)
        doc = Nokogiri::XML(wf_xml)
        doc.xpath('/workflow/process').each { |proc| proc['priority'] = priority }
        doc.to_xml
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
      # @option opts [Integer] :priority Processing priority. Recommended range is -100..100, 100 being the highest priority, and -100 being the lowest priority. Workflow queues are returned in order of highest to lowest priority value. Default is 0.
      # @return [Boolean] always true
      # Http Call
      # ==
      # The method does an HTTP PUT to the URL defined in `Dor::WF_URI`.  As an example:
      #
      #     PUT "/dor/objects/pid:123/workflows/GoogleScannedWF/convert"
      #     <process name=\"convert\" status=\"completed\" />"
      def update_workflow_status(repo, druid, workflow, process, status, opts = {})
        raise ArgumentError, "Unknown status value #{status}" unless VALID_STATUS.include?(status.downcase)
        opts = {:elapsed => 0, :lifecycle => nil, :note => nil}.merge!(opts)
        opts[:elapsed] = opts[:elapsed].to_s
        xml = create_process_xml({:name => process, :status => status.downcase}.merge!(opts))
        workflow_resource["#{repo}/objects/#{druid}/workflows/#{workflow}/#{process}"].put(xml, :content_type => 'application/xml')
        return true
      end

      #
      # Retrieves the process status of the given workflow for the given object identifier
      # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
      # @param [String] druid The id of the object
      # @param [String] workflow The name of the workflow
      # @param [String] process The name of the process step
      # @return [String] status for repo-workflow-process-druid
      def get_workflow_status(repo, druid, workflow, process)
        workflow_md = get_workflow_xml(repo, druid, workflow)
        doc = Nokogiri::XML(workflow_md)
        raise Exception.new("Unable to parse response:\n#{workflow_md}") if(doc.root.nil?)

        status = doc.root.at_xpath("//process[@name='#{process}']/@status")
        if status
          status=status.content
        end
        return status
      end

      #
      # Retrieves the raw XML for the given workflow
      # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
      # @param [String] druid The id of the object
      # @param [String] workflow The name of the workflow
      # @return [String] XML of the workflow
      def get_workflow_xml(repo, druid, workflow)
        workflow_resource["#{repo}/objects/#{druid}/workflows/#{workflow}"].get
      end

      # Get workflow names into an array for given PID
      # This method only works when this gem is used in a project that is configured to connect to DOR
      #
      # @param [String] pid of druid
      # @return [Array<String>] list of worklows
      # @example 
      #   Dor::WorkflowService.get_workflows('druid:sr100hp0609')
      #   => ["accessionWF", "assemblyWF", "disseminationWF"]
      def get_workflows(pid)
        xml_doc=Nokogiri::XML(get_workflow_xml('dor',pid,''))
        return xml_doc.xpath('//workflow').collect {|workflow| workflow['id']}
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
        doc = Nokogiri::XML(get_workflow_xml(repo,pid,''))
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
      # @option opts [String] :error_txt A slot to hold more information about the error, like a full stacktrace
      # @return [Boolean] always true
      #
      # Http Call
      # ==
      # The method does an HTTP PUT to the URL defined in `Dor::WF_URI`.
      #
      #     PUT "/dor/objects/pid:123/workflows/GoogleScannedWF/convert"
      #     <process name=\"convert\" status=\"error\" />"
      def update_workflow_error_status(repo, druid, workflow, process, error_msg, opts = {})
        opts = {:error_txt => nil}.merge!(opts)
        xml = create_process_xml({:name => process, :status => 'error', :errorMessage => error_msg}.merge!(opts))
        workflow_resource["#{repo}/objects/#{druid}/workflows/#{workflow}/#{process}"].put(xml, :content_type => 'application/xml')
        return true
      end

      # Deletes a workflow from a particular repository and druid
      # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
      # @param [String] druid The id of the object to delete the workflow from
      # @param [String] workflow The name of the workflow to be deleted
      # @return [Boolean] always true
      def delete_workflow(repo, druid, workflow)
        workflow_resource["#{repo}/objects/#{druid}/workflows/#{workflow}"].delete
        return true
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
        doc = self.query_lifecycle(repo, druid)
        milestone = doc.at_xpath("//lifecycle/milestone[text() = '#{milestone}']")
        if(milestone)
          return Time.parse(milestone['date'])
        end

        nil
      end

      # Returns the Date for a requested milestone ONLY FROM THE ACTIVE workflow table
      # @param [String] repo epository name
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
        doc = self.query_lifecycle(repo, druid, true)
        milestone = doc.at_xpath("//lifecycle/milestone[text() = '#{milestone}']")
        if(milestone)
          return Time.parse(milestone['date'])
        end

        nil
      end

      # @return [Hash]
      def get_milestones(repo, druid)
        doc = self.query_lifecycle(repo, druid)
        doc.xpath("//lifecycle/milestone").collect do |node|
          { :milestone => node.text, :at => Time.parse(node['date']), :version => node['version'] }
        end
      end

      # Converts repo-workflow-step into repo:workflow:step
      # @param [String] default_repository
      # @param [String] default_workflow
      # @param [String] step if contains colon :, then uses
      #   the value for workflow and/or workflow/repository.
      #   for example, jp2-create, or assemblyWF:jp2-create,
      #   or dor:assemblyWF:jp2-create
      # @return [String] repo:workflow:step
      # @example 
      #   dor:assemblyWF:jp2-create
      def qualify_step(default_repository, default_workflow, step)
        current = step.split(/:/,3)
        current.unshift(default_workflow) if current.length < 3
        current.unshift(default_repository) if current.length < 3
        current.join(':')
      end

      # Returns a list of druids from the WorkflowService that meet the criteria of the passed in completed and waiting params
      #
      # @param [Array<String>, String] completed An array or single String of the completed steps, should use the qualified format: `repository:workflow:step-name`
      # @param [String] waiting name of the waiting step
      # @param [String] repository default repository to use if it isn't passed in the qualified-step-name
      # @param [String] workflow default workflow to use if it isn't passed in the qualified-step-name
      # @param [Hash] options
      # @option options [Boolean] :with_priority include the priority with each druid
      # @option options [Integer] :limit maximum number of druids to return (nil for no limit)
      # @return [Array<String>, Hash] if with_priority, hash with druids as keys with their Integer priority as value; else Array of druids
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
      #     get_objects_for_workstep(..., with_priority: true) 
      #     => {
      #      "druid:py156ps0477" => 100,
      #      "druid:tt628cb6479" => 0,
      #      "druid:ct021wp7863" => -100
      #     }
      #
      def get_objects_for_workstep completed, waiting, repository=nil, workflow=nil, options = {}
        result = nil
        uri_string = "workflow_queue?waiting=#{qualify_step(repository,workflow,waiting)}"
        if(completed)
          Array(completed).each do |step|
            uri_string << "&completed=#{qualify_step(repository,workflow,step)}"
          end
        end

        if options[:limit] and options[:limit].to_i > 0
          uri_string << "&limit=#{options[:limit].to_i}"
        end

        workflow_resource.options[:timeout] = 5 * 60 unless(workflow_resource.options.include?(:timeout))
        resp = workflow_resource[uri_string].get
        #
        # response looks like:
        #    <objects count="2">
        #      <object id="druid:ab123de4567" priority="2"/>
        #      <object id="druid:ab123de9012" priority="1"/>        #
        #    </objects>
        #
        # convert into:
        #    { 'druid:ab123de4567' => 2, 'druid:ab123de9012' => 1}
        #
        result = Nokogiri::XML(resp).xpath('//object[@id]').inject({}) do |h, node|
          h[node['id']] = node['priority'] ? node['priority'].to_i : 0
          h
        end

        options[:with_priority] ? result : result.keys
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
      def get_errored_objects_for_workstep workflow, step, repository='dor'
        result = {}
        uri_string = "workflow_queue?repository=#{repository}&workflow=#{workflow}&error=#{step}"
        resp = workflow_resource[uri_string].get
        objs = Nokogiri::XML(resp).xpath('//object').collect do |node|
          result.merge!(node['id'] => node['errorMessage'])
        end
        result
      end

      # @return [String]
      def create_process_xml(params)
        builder = Nokogiri::XML::Builder.new do |xml|
          attrs = params.reject { |k,v| v.nil? }
          xml.process(attrs)
        end
        return builder.to_xml
      end

      # @return [Nokogiri::XML::Document]
      def query_lifecycle(repo, druid, active_only = false)
        req = "#{repo}/objects/#{druid}/lifecycle"
        req << '?active-only=true' if active_only
        lifecycle_xml = workflow_resource[req].get
        return Nokogiri::XML(lifecycle_xml)
      end

      def archive_active_workflow(repo, druid)
        workflows = get_active_workflows(repo, druid)
        workflows.each do |wf|
          archive_workflow(repo, druid, wf)
        end
      end

      def archive_workflow(repo, druid, wf_name, version_num=nil)
        raise "Please call Dor::WorkflowService.configure(workflow_service_url, :dor_services_url => DOR_SERVIES_URL) once before archiving workflow" if(@@dor_services_url.nil?)

        dor_services = RestClient::Resource.new(@@dor_services_url)
        url = "/v1/objects/#{druid}/workflows/#{wf_name}/archive"
        url << "/#{version_num}" if(version_num)
        dor_services[url].post ''
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
        uri << "?create-accession=false" if(!create_accession_wf)
        workflow_resource[uri].post ''
        return true
      end

      # @return [RestClient::Resource] the REST client resource
      def workflow_resource
        raise "Please call Dor::WorkflowService.configure(url) once before calling any WorkflowService methods" if(@@resource.nil?)
        @@resource
      end

      # Configure the workflow service
      #
      # @param [String] url points to the workflow service
      # @param [Hash] opts optional params
      # @option opts [String] :dor_services_uri uri to the DOR REST service
      # @option opts [Integer] :timeout number of seconds for RestClient timeout
      # @option opts [String] :client_cert_file path to an SSL client certificate (deprecated)
      # @option opts [String] :client_key_file path to an SSL key file (deprecated)
      # @option opts [String] :client_key_pass password for the key file (deprecated)
      # @return [RestClient::Resource] the REST client resource
      def configure(url, opts={})
        params = {}
        params[:timeout] = opts[:timeout] if opts[:timeout]
        @@dor_services_url = opts[:dor_services_url] if opts[:dor_services_url]
        #params[:ssl_client_cert] = OpenSSL::X509::Certificate.new(File.read(opts[:client_cert_file])) if opts[:client_cert_file]
        #params[:ssl_client_key]  = OpenSSL::PKey::RSA.new(File.read(opts[:client_key_file]), opts[:client_key_pass]) if opts[:client_key_file]
        @@resource = RestClient::Resource.new(url, params)
      end

    end
  end
end
