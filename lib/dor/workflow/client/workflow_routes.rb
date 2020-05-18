# frozen_string_literal: true

module Dor
  module Workflow
    class Client
      # Makes requests relating to a workflow
      # rubocop:disable Metrics/ClassLength
      class WorkflowRoutes
        extend Deprecation

        def initialize(requestor:)
          @requestor = requestor
        end

        # This method is deprecated and calls create_workflow_by_name.
        #
        # @param [String] repo Ignored
        # @param [String] druid The id of the object
        # @param [String] workflow_name The name of the workflow you want to create
        # @param [String] wf_xml Ignored
        # @param [Hash] opts optional params
        # @option opts [String] :lane_id adds laneId attribute to all process elements in the wf_xml workflow xml.  Defaults to a value of 'default'
        # @return [Boolean] always true
        #
        def create_workflow(_repo, druid, workflow_name, _wf_xml, opts = {})
          create_workflow_by_name(druid, workflow_name, opts)
        end
        deprecation_deprecate create_workflow: 'use create_workflow_by_name instead'

        # Creates a workflow for a given object in the repository.  If this particular workflow for this objects exists,
        # it will replace the old workflow.  You have the option of creating a datastream or not.
        # Returns true on success.  Caller must handle any exceptions.
        #
        # @param [String] druid The id of the object
        # @param [String] workflow_name The name of the workflow you want to create. This must correspond with a workflow
        # name that is known by the workflow service.
        # @param [String] lane_id adds laneId attribute to all process elements in the wf_xml workflow xml.  Defaults to a value of 'default'
        # @param [Integer] version specifies the version so that workflow service doesn't need to query dor-services.
        # @return [Boolean] always true
        #
        def create_workflow_by_name(druid, workflow_name, version: nil, lane_id: 'default')
          params = { 'lane-id' => lane_id }
          if version
            params['version'] = version
          else
            Deprecation.warn(self, 'Calling create_workflow_by_name without passing version is deprecated and will result in an error in dor-workflow-client 4.0')
          end
          requestor.request "objects/#{druid}/workflows/#{workflow_name}", 'post', '',
                            content_type: 'application/xml',
                            params: params
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
        # @param [Float] :elapsed The number of seconds it took to complete this step. Can have a decimal.  Is set to 0 if not passed in.
        # @param [String] :lifecycle Bookeeping label for this particular workflow step.  Examples are: 'registered', 'shelved'
        # @param [String] :note Any kind of string annotation that you want to attach to the workflow
        # @param [String] :current_status Setting this string tells the workflow service to compare the current status to this value.  If the current value does not match this value, the update is not performed
        # @return [Boolean] always true
        # Http Call
        # ==
        # The method does an HTTP PUT to the base URL.  As an example:
        #
        #     PUT "/objects/pid:123/workflows/GoogleScannedWF/convert"
        #     <process name=\"convert\" status=\"completed\" />"
        def update_status(druid:, workflow:, process:, status:, elapsed: 0, lifecycle: nil, note: nil, current_status: nil)
          raise ArgumentError, "Unknown status value #{status}" unless VALID_STATUS.include?(status)
          raise ArgumentError, "Unknown current_status value #{current_status}" if current_status && !VALID_STATUS.include?(current_status)

          xml = create_process_xml(name: process, status: status, elapsed: elapsed, lifecycle: lifecycle, note: note)
          uri = "objects/#{druid}/workflows/#{workflow}/#{process}"
          uri += "?current-status=#{current_status}" if current_status
          response = requestor.request(uri, 'put', xml, content_type: 'application/xml')

          Workflow::Response::Update.new(json: response)
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
        # The method does an HTTP PUT to the base URL.  As an example:
        #
        #     PUT "/dor/objects/pid:123/workflows/GoogleScannedWF/convert"
        #     <process name=\"convert\" status=\"completed\" />"
        def update_workflow_status(repo, druid, workflow, process, status, opts = {})
          raise ArgumentError, "Unknown status value #{status}" unless VALID_STATUS.include?(status.downcase)

          opts = { elapsed: 0, lifecycle: nil, note: nil }.merge!(opts)
          opts[:elapsed] = opts[:elapsed].to_s
          current_status = opts.delete(:current_status)
          xml = create_process_xml({ name: process, status: status.downcase }.merge!(opts))
          uri = "#{repo}/objects/#{druid}/workflows/#{workflow}/#{process}"
          uri += "?current-status=#{current_status.downcase}" if current_status
          response = requestor.request(uri, 'put', xml, content_type: 'application/xml')
          Workflow::Response::Update.new(json: response)
        end
        deprecation_deprecate update_workflow_status: 'use update_status instead.'

        #
        # Retrieves the process status of the given workflow for the given object identifier
        # @param [String] repo The repository the object resides in.  Currently recoginzes "dor" and "sdr".
        # @param [String] druid The id of the object
        # @param [String] workflow The name of the workflow
        # @param [String] process The name of the process step
        # @return [String] status for repo-workflow-process-druid
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/AbcSize
        def workflow_status(*args)
          case args.length
          when 4
            Deprecation.warn(self, 'Calling workflow_status with positional args is deprecated, use kwargs instead')
            (_repo, druid, workflow, process) = *args
          when 1
            opts = args.first
            repo = opts[:repo]
            Deprecation.warn(self, 'Passing `:repo` to workflow_status is deprecated and can be omitted') if repo
            druid = opts[:druid]
            workflow = opts[:workflow]
            process = opts[:process]
          end
          workflow_md = fetch_workflow(druid: druid, workflow: workflow)
          doc = Nokogiri::XML(workflow_md)
          raise Dor::WorkflowException, "Unable to parse response:\n#{workflow_md}" if doc.root.nil?

          processes = doc.root.xpath("//process[@name='#{process}']")
          process = processes.max { |a, b| a.attr('version').to_i <=> b.attr('version').to_i }
          process&.attr('status')
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        #
        # Retrieves the raw XML for the given workflow
        # @param [String] repo The repository the object resides in.  Currently recoginzes "dor" and "sdr".
        # @param [String] druid The id of the object
        # @param [String] workflow The name of the workflow
        # @return [String] XML of the workflow
        # rubocop:disable Metrics/MethodLength
        def workflow_xml(*args)
          case args.length
          when 3
            Deprecation.warn(self, 'Calling workflow_xml with positional args is deprecated, use kwargs instead')
            (repo, druid, workflow) = *args
          when 1
            opts = args.first
            repo = opts[:repo]
            Deprecation.warn(self, 'Passing `:repo` to workflow_xml is deprecated and can be omitted') if repo
            druid = opts[:druid]
            workflow = opts[:workflow]
          end

          raise ArgumentError, 'missing workflow' unless workflow
          return requestor.request "#{repo}/objects/#{druid}/workflows/#{workflow}" if repo

          fetch_workflow(druid: druid, workflow: workflow)
        end
        deprecation_deprecate workflow_xml: 'workflow_xml will not be replaced'

        # rubocop:enable Metrics/MethodLength

        # Updates the status of one step in a workflow to error.
        # Returns true on success.  Caller must handle any exceptions
        #
        # @param [String] _repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
        # @param [String] druid The id of the object
        # @param [String] workflow The name of the workflow
        # @param [String] process The name of the workflow step
        # @param [String] error_msg The error message.  Ideally, this is a brief message describing the error
        # @param [Hash] opts optional values for the workflow step
        # @option opts [String] :error_text A slot to hold more information about the error, like a full stacktrace
        # @return [Boolean] always true
        #
        # Http Call
        # ==
        # The method does an HTTP PUT to the base URL.
        #
        #     PUT "/objects/pid:123/workflows/GoogleScannedWF/convert"
        #     <process name=\"convert\" status=\"error\" />"
        def update_workflow_error_status(_repo, druid, workflow, process, error_msg, opts = {})
          update_error_status(druid: druid, workflow: workflow, process: process, error_msg: error_msg, error_text: opts[:error_text])
          true
        end
        deprecation_deprecate update_workflow_error_status: 'use update_error_status instead.'

        # Updates the status of one step in a workflow to error.
        # Returns true on success.  Caller must handle any exceptions
        #
        # @param [String] druid The id of the object
        # @param [String] workflow The name of the workflow
        # @param [String] process The name of the workflow step
        # @param [String] error_msg The error message.  Ideally, this is a brief message describing the error
        # @param [String] error_text A slot to hold more information about the error, like a full stacktrace
        # @return [Workflow::Response::Update]
        #
        # Http Call
        # ==
        # The method does an HTTP PUT to the base URL.
        #
        #     PUT "/objects/pid:123/workflows/GoogleScannedWF/convert"
        #     <process name=\"convert\" status=\"error\" />"
        def update_error_status(druid:, workflow:, process:, error_msg:, error_text: nil)
          xml = create_process_xml(name: process, status: 'error', errorMessage: error_msg, error_text: error_text)
          response = requestor.request "objects/#{druid}/workflows/#{workflow}/#{process}", 'put', xml, content_type: 'application/xml'
          Workflow::Response::Update.new(json: response)
        end

        #
        # Retrieves the raw XML for all the workflows for the the given object
        # @param [String] druid The id of the object
        # @return [String] XML of the workflow
        def all_workflows_xml(druid)
          requestor.request "objects/#{druid}/workflows"
        end

        # Retrieves all workflows for the given object
        # @param [String] pid The id of the object
        # @return [Workflow::Response::Workflows]
        def all_workflows(pid:)
          xml = all_workflows_xml(pid)
          Workflow::Response::Workflows.new(xml: xml)
        end

        # Get workflow names into an array for given PID
        # This method only works when this gem is used in a project that is configured to connect to DOR
        #
        # @param [String] pid of druid
        # @param [String] repo repository for the object
        # @return [Array<String>] list of worklows
        # @example
        #   client.workflows('druid:sr100hp0609')
        #   => ["accessionWF", "assemblyWF", "disseminationWF"]
        def workflows(pid, repo = nil)
          Deprecation.warn(self, 'Passing the second argument (repo) to workflows is deprecated and can be omitted') if repo
          xml_doc = Nokogiri::XML(fetch_workflow(druid: pid, workflow: ''))
          xml_doc.xpath('//workflow').collect { |workflow| workflow['id'] }
        end

        # @param [String] repo repository of the object
        # @param [String] pid id of object
        # @param [String] workflow_name The name of the workflow
        # @return [Workflow::Response::Workflow]
        def workflow(repo: nil, pid:, workflow_name:)
          Deprecation.warn(self, 'passing the repo parameter is deprecated and will be removed in the next major versions') if repo
          xml = fetch_workflow(druid: pid, workflow: workflow_name)
          Workflow::Response::Workflow.new(xml: xml)
        end

        # @param [String] pid id of object
        # @param [String] workflow_name The name of the workflow
        # @param [String] process The name of the workflow step
        # @return [Workflow::Response::Process]
        def process(pid:, workflow_name:, process:)
          workflow(pid: pid, workflow_name: workflow_name).process_for_recent_version(name: process)
        end

        # Deletes a workflow from a particular repository and druid. This is only used by Hydrus.
        # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
        # @param [String] druid The id of the object to delete the workflow from
        # @param [String] workflow The name of the workflow to be deleted
        # @param [Integer] version The version of the workflow to delete
        # @return [Boolean] always true
        def delete_workflow(repo, druid, workflow, version: nil)
          qs_args = if version
                      "?version=#{version}"
                    else
                      Deprecation.warn(self, 'Calling delete_workflow without passing version is deprecated and will result in an error in dor-workflow-client 4.0')
                      ''
                    end
          requestor.request "#{repo}/objects/#{druid}/workflows/#{workflow}#{qs_args}", 'delete'
          true
        end

        # Deletes all workflow steps for a particular druid
        # @param [String] pid The id of the object to delete the workflow from
        # @return [Boolean] always true
        def delete_all_workflows(pid:)
          requestor.request "objects/#{pid}/workflows", 'delete'
          true
        end

        private

        attr_reader :requestor

        def fetch_workflow(druid:, workflow:)
          raise ArgumentError, 'missing workflow' unless workflow

          requestor.request "objects/#{druid}/workflows/#{workflow}"
        end

        # @param [Hash] params
        # @return [String]
        def create_process_xml(params)
          builder = Nokogiri::XML::Builder.new do |xml|
            attrs = params.reject { |_k, v| v.nil? }
            attrs = Hash[attrs.map { |k, v| [k.to_s.camelize(:lower), v] }] # camelize all the keys in the attrs hash
            xml.process(attrs)
          end
          builder.to_xml
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
