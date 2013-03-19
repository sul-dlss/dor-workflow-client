require 'rest-client'
require 'active_support/core_ext'
require 'nokogiri'

module Dor

  # Methods to create and update workflow
  module WorkflowService
    class << self

      @@resource = nil
      @@dor_services_url = nil

      # Creates a workflow for a given object in the repository.  If this particular workflow for this objects exists,
      # it will replace the old workflow with wf_xml passed to this method.  You have the option of creating a datastream or not.
      # Returns true on success.  Caller must handle any exceptions
      #
      # == Parameters
      # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
      # @param [String] druid The id of the object
      # @param [String] workflow_name The name of the workflow you want to create
      # @param [String] wf_xml The xml that represents the workflow
      # @param [Hash] opts optional params
      # @option opts [Boolean] :create_ds if true, a workflow datastream will be created in Fedora.  Set to false if you do not want a datastream to be created
      #   If you do not pass in an <b>opts</b> Hash, then :create_ds is set to true by default
      #
      def create_workflow(repo, druid, workflow_name, wf_xml, opts = {:create_ds => true})
        workflow_resource["#{repo}/objects/#{druid}/workflows/#{workflow_name}"].put(wf_xml, :content_type => 'application/xml',
                                                                                     :params => {'create-ds' => opts[:create_ds] })
        return true
      end

      # Updates the status of one step in a workflow.
      # Returns true on success.  Caller must handle any exceptions
      #
      # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
      # @param [String] druid The id of the object
      # @param [String] workflow The name of the workflow
      # @param [String] status The status that you want to set.  Typical statuses are 'waiting', 'completed', 'error', but could be any string
      # @param [Hash] opts optional values for the workflow step
      # @option opts [Float] :elapsed The number of seconds it took to complete this step. Can have a decimal.  Is set to 0 if not passed in.
      # @option opts [String] :lifecycle Bookeeping label for this particular workflow step.  Examples are: 'registered', 'shelved'
      # @option opts [String] :note Any kind of string annotation that you want to attach to the workflow
      # == Http Call
      # The method does an HTTP PUT to the URL defined in Dor::WF_URI.  As an example:
      #   PUT "/dor/objects/pid:123/workflows/GoogleScannedWF/convert"
      #   <process name=\"convert\" status=\"completed\" />"
      def update_workflow_status(repo, druid, workflow, process, status, opts = {}) #elapsed = 0, lifecycle = nil)
        opts = {:elapsed => 0, :lifecycle => nil, :note => nil}.merge!(opts)
        opts[:elapsed] = opts[:elapsed].to_s
        xml = create_process_xml({:name => process, :status => status}.merge!(opts))
        workflow_resource["#{repo}/objects/#{druid}/workflows/#{workflow}/#{process}"].put(xml, :content_type => 'application/xml')
        return true
      end

      #
      # Retrieves the process status of the given workflow for the given object identifier
      #
      def get_workflow_status(repo, druid, workflow, process)
        workflow_md = workflow_resource["#{repo}/objects/#{druid}/workflows/#{workflow}"].get
        doc = Nokogiri::XML(workflow_md)
        raise Exception.new("Unable to parse response:\n#{workflow_md}") if(doc.root.nil?)

        status = doc.root.at_xpath("//process[@name='#{process}']/@status")
        if status
          status=status.content
        end
        return status
      end

      def get_workflow_xml(repo, druid, workflow)
        workflow_resource["#{repo}/objects/#{druid}/workflows/#{workflow}"].get
      end

      # Get workflow names into an array for given PID
      # This method only works when this gem is used in a project that is configured to connect to DOR
      #
      # @param [string] pid of druid
      #
      # @return [array] list of worklows
      # e.g.
      # Dor::WorkflowService.get_workflows('druid:sr100hp0609')
      # => ["accessionWF", "assemblyWF", "disseminationWF"]
      def get_workflows(pid)
        xml_doc=Nokogiri::XML(get_workflow_xml('dor',pid,''))
        return xml_doc.xpath('//workflow').collect {|workflow| workflow['id']}
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
      #
      # == Http Call
      # The method does an HTTP PUT to the URL defined in Dor::WF_URI.  As an example:
      #   PUT "/dor/objects/pid:123/workflows/GoogleScannedWF/convert"
      #   <process name=\"convert\" status=\"error\" />"
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
      def delete_workflow(repo, druid, workflow)
        workflow_resource["#{repo}/objects/#{druid}/workflows/#{workflow}"].delete
        return true
      end

      # Returns the Date for a requested milestone from workflow lifecycle
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

      def get_milestones(repo, druid)
        doc = self.query_lifecycle(repo, druid)
        doc.xpath("//lifecycle/milestone").collect do |node|
          { :milestone => node.text, :at => Time.parse(node['date']), :version => node['version'] }
        end
      end

      def qualify_step(default_repository, default_workflow, step)
        current = step.split(/:/,3)
        current.unshift(default_workflow) if current.length < 3
        current.unshift(default_repository) if current.length < 3
        current.join(':')
      end

      # This method bunches up groups of 2 completed steps and builds qualified (repository:workflow:step) paramaters
      # for the workflow service
      # TODO when we switch the workflow service to handle joins of more than 2 completed steps, we can fix this method to do one query
      def get_objects_for_workstep completed, waiting, repository=nil, workflow=nil
        result = nil
        if(completed)
          Array(completed).in_groups_of(2,false).each do |group|
            uri_string = "workflow_queue?waiting=#{qualify_step(repository,workflow,waiting)}"
            group.each { |step| uri_string << "&completed=#{qualify_step(repository,workflow,step)}" }
            resp = workflow_resource[uri_string].get
            resp_ids = Nokogiri::XML(resp).xpath('//object[@id]').collect { |node| node['id'] }
            result = result.nil? ? resp_ids : (result & resp_ids)
          end
        else
          uri_string = "workflow_queue?waiting=#{qualify_step(repository,workflow,waiting)}"
          resp = workflow_resource[uri_string].get
          result = Nokogiri::XML(resp).xpath('//object[@id]').collect { |node| node['id'] }
        end

        result || []
      end

      # Get a list of druids that have errored out in a particular workflow and step
      #
      # @param [string] workflow name
      # @param [string] step name
      # @param [string] repository -- optional, default=dor
      #
      # @return [hash] hash of results, with key has a druid, and value as the error message
      # e.g.
      # Dor::WorkflowService.get_errored_objects_for_workstep('accessionWF','content-metadata')
      # => {"druid:qd556jq0580"=>"druid:qd556jq0580 - Item error; caused by #<Rubydora::FedoraInvalidRequest: Error modifying datastream contentMetadata for druid:qd556jq0580. See logger for details>"}
      def get_errored_objects_for_workstep workflow, step, repository='dor'
        result = {}
        uri_string = "workflow_queue?repository=#{repository}&workflow=#{workflow}&error=#{step}"
        resp = workflow_resource[uri_string].get
        objs = Nokogiri::XML(resp).xpath('//object').collect do |node|
          result.merge!(node['id'] => node['errorMessage'])
        end
        result
      end

      def create_process_xml(params)
        builder = Nokogiri::XML::Builder.new do |xml|
          attrs = params.reject { |k,v| v.nil? }
          xml.process(attrs)
        end
        return builder.to_xml
      end

      def query_lifecycle(repo, druid, active_only = false)
        req = "#{repo}/objects/#{druid}/lifecycle"
        req << '?active-only=true' if active_only
        lifecycle_xml = workflow_resource[req].get
        return Nokogiri::XML(lifecycle_xml)
      end

      def archive_workflow(repo, druid, wf_name, version_num=nil)
        raise "Please call Dor::WorkflowService.configure(workflow_service_url, :dor_services_url => DOR_SERVIES_URL) once before archiving workflow" if(@@dor_services_url.nil?)

        dor_services = RestClient::Resource.new(@@dor_services_url)
        url = "/v1/objects/#{druid}/workflows/#{wf_name}/archive"
        url << "/#{version_num}" if(version_num)
        dor_services[url].post ''
      end

      def workflow_resource
        raise "Please call Dor::WorkflowService.configure(url) once before calling any WorkflowService methods" if(@@resource.nil?)
        @@resource
      end

      # @param [String] url points to the workflow service
      # @param [Hash] opts optional params
      # @option opts [String] :client_cert_file path to an SSL client certificate
      # @option opts [String] :client_key_file path to an SSL key file
      # @option opts [String] :client_key_pass password for the key file
      # @option opts [String] :dor_services_uri uri to the DOR REST service
      def configure(url, opts={})
        params = {}
        @@dor_services_url = opts[:dor_services_url] if opts[:dor_services_url]
        #params[:ssl_client_cert] = OpenSSL::X509::Certificate.new(File.read(opts[:client_cert_file])) if opts[:client_cert_file]
        #params[:ssl_client_key]  = OpenSSL::PKey::RSA.new(File.read(opts[:client_key_file]), opts[:client_key_pass]) if opts[:client_key_file]
        @@resource = RestClient::Resource.new(url, params)
      end

    end
  end
end
