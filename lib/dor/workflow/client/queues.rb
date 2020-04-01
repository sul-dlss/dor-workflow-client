# frozen_string_literal: true

module Dor
  module Workflow
    class Client
      # Makes requests relating to the workflow queues
      class Queues
        def initialize(requestor:)
          @requestor = requestor
        end

        # Returns all the distinct laneIds for a given workflow step
        #
        # @param [String] repo -- deprecated, ignored by workflow service
        # @param [String] workflow name
        # @param [String] process name
        # @return [Array<String>] all of the distinct laneIds.  Array will be empty if no lane ids were found
        def lane_ids(*args)
          if args.count == 3
            Deprecation.warn(
              self,
              '`#lane_ids` only takes two args: workflow name, & process/step name. This will raise an exception in Dor::Workflow::Client 4.0.0'
            )
            args.shift # ditch the `repo` argument
          end
          uri = "workflow_queue/lane_ids?step=#{args.first}:#{args.second}"
          doc = Nokogiri::XML(requestor.request(uri))
          doc.xpath('/lanes/lane').map { |n| n['id'] }
        end

        # Gets all of the workflow steps that have a status of 'queued' that have a last-updated timestamp older than the number of hours passed in
        #   This will enable re-queueing of jobs that have been lost by the job manager
        # @param [String] repository -- deprecated, ignored by workflow service
        # @param [Hash] opts optional values for query
        # @option opts [Integer] :hours_ago steps older than this value will be returned by the query.  If not passed in, the service defaults to 0 hours,
        #   meaning you will get all queued workflows
        # @option opts [Integer] :limit sets the maximum number of workflow steps that can be returned.  Defaults to no limit
        # @return [Array[Hash]] each Hash represents a workflow step.  It will have the following keys:
        #  :workflow, :step, :druid, :lane_id
        def stale_queued_workflows(*args)
          if args.count == 2
            Deprecation.warn(
              self,
              '`#stale_queued_workflows` only takes one arg: a hash. This will raise an exception in Dor::Workflow::Client 4.0.0'
            )
            args.shift # ditch the `repo` argument
          end
          uri_string = build_queued_uri(args.first)
          parse_queued_workflows_response requestor.request(uri_string)
        end

        # Returns a count of workflow steps that have a status of 'queued' that have a last-updated timestamp older than the number of hours passed in
        # @param [String] repository -- deprecated, ignored by workflow service
        # @param [Hash] opts optional values for query
        # @option opts [Integer] :hours_ago steps older than this value will be returned by the query.  If not passed in, the service defaults to 0 hours,
        #   meaning you will get all queued workflows
        # @return [Integer] number of stale, queued steps if the :count_only option was set to true
        def count_stale_queued_workflows(*args)
          if args.count == 2
            Deprecation.warn(
              self,
              '`#count_stale_queued_workflows` only takes one arg: a hash. This will raise an exception in Dor::Workflow::Client 4.0.0'
            )
            args.shift # ditch the `repo` argument
          end
          uri_string = build_queued_uri(args.first) + '&count-only=true'
          doc = Nokogiri::XML(requestor.request(uri_string))
          doc.at_xpath('/objects/@count').value.to_i
        end

        # Returns a list of druids from the workflow service that meet the criteria
        # of the passed in completed and waiting params
        #
        # @param [Array<String>, String] completed An array or single String of the completed steps, should use the qualified format: `workflow:step-name`
        # @param [String] waiting name of the waiting step
        # @param [String] workflow default workflow to use if it isn't passed in the qualified-step-name
        # @param [String] lane_id issue a query for a specific lane_id for the waiting step
        # @param [Hash] options
        # @param options  [String]  :default_workflow workflow to query for if not using the qualified format
        # @option options [Integer] :limit maximum number of druids to return (nil for no limit)
        # @return [Array<String>]  Array of druids
        #
        # @example
        #     objects_for_workstep(...)
        #     => [
        #        "druid:py156ps0477",
        #        "druid:tt628cb6479",
        #        "druid:ct021wp7863"
        #      ]
        #
        # @example
        #     objects_for_workstep(..., "lane1")
        #     => {
        #      "druid:py156ps0477",
        #      "druid:tt628cb6479",
        #     }
        #
        # @example
        #     objects_for_workstep(..., "lane1", limit: 1)
        #     => {
        #      "druid:py156ps0477",
        #     }
        #
        def objects_for_workstep(completed, waiting, lane_id = 'default', options = {})
          Deprecation.warn(self, 'the `:default_repository` option in `#objects_for_workstep` is unused and will go away in Dor::Workflow::Client 4.0.0. omit argument to silence.') if options[:default_repository]
          waiting_param = qualify_step(options[:default_workflow], waiting)
          uri_string = "workflow_queue?waiting=#{waiting_param}"
          if completed
            Array(completed).each do |step|
              completed_param = qualify_step(options[:default_workflow], step)
              uri_string += "&completed=#{completed_param}"
            end
          end

          uri_string += "&limit=#{options[:limit].to_i}" if options[:limit]&.to_i&.positive?
          uri_string += "&lane-id=#{lane_id}"

          resp = requestor.request uri_string
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
        #
        # @param [String] workflow name
        # @param [String] step name
        # @param [String] repository -- deprecated, ignored by workflow service
        #
        # @return [Hash] hash of results, with key has a druid, and value as the error message
        # @example
        #     client.errored_objects_for_workstep('accessionWF','content-metadata')
        #     => {"druid:qd556jq0580"=>"druid:qd556jq0580 - Item error; caused by
        #        #<Rubydora::FedoraInvalidRequest: Error modifying datastream contentMetadata for druid:qd556jq0580. See logger for details>"}
        def errored_objects_for_workstep(workflow, step, repository = nil)
          Deprecation.warn(self, 'the third argument to `#errored_objects_for_workstep` is unused and will go away in Dor::Workflow::Client 4.0.0. omit argument to silence.') unless repository.nil?
          resp = requestor.request "workflow_queue?workflow=#{workflow}&error=#{step}"
          Nokogiri::XML(resp).xpath('//object').map do |node|
            [node['id'], node['errorMessage']]
          end.to_h
        end

        # Used by preservation robots stats reporter
        #
        # @param [String] workflow name
        # @param [String] step name
        # @param [String] type
        # @param [String] repo -- deprecated, ignored by workflow service
        #
        # @return [Hash] hash of results, with key has a druid, and value as the error message
        def count_objects_in_step(workflow, step, type, repo = nil)
          Deprecation.warn(self, 'the fourth argument to `#count_objects_in_step` is unused and will go away in Dor::Workflow::Client 4.0.0. omit argument to silence.') unless repo.nil?
          resp = requestor.request "workflow_queue?workflow=#{workflow}&#{type}=#{step}"
          extract_object_count(resp)
        end

        # Returns the number of objects that have a status of 'error' in a particular workflow and step
        #
        # @param [String] workflow name
        # @param [String] step name
        # @param [String] repository -- deprecated, ignored by workflow service
        #
        # @return [Integer] Number of objects with this repository:workflow:step that have a status of 'error'
        def count_errored_for_workstep(workflow, step, repository = nil)
          Deprecation.warn(self, 'the third argument to `#count_errored_for_workstep` is unused and will go away in Dor::Workflow::Client 4.0.0. omit argument to silence.') unless repository.nil?
          count_objects_in_step(workflow, step, 'error')
        end

        # Returns the number of objects that have a status of 'queued' in a particular workflow and step
        #
        # @param [String] workflow name
        # @param [String] step name
        # @param [String] repository -- deprecated, ignored by workflow service
        #
        # @return [Integer] Number of objects with this repository:workflow:step that have a status of 'queued'
        def count_queued_for_workstep(workflow, step, repository = nil)
          Deprecation.warn(self, 'the third argument to `#count_queued_for_workstep` is unused and will go away in Dor::Workflow::Client 4.0.0. omit argument to silence.') unless repository.nil?
          count_objects_in_step(workflow, step, 'queued')
        end

        private

        attr_reader :requestor

        def build_queued_uri(opts = {})
          query_hash = opts.slice(:hours_ago, :limit).transform_keys { |key| key.to_s.tr('_', '-') }
          query_string = URI.encode_www_form(query_hash)
          "workflow_queue/all_queued?#{query_string}"
        end

        # Converts workflow-step into workflow:step
        # @param [String] default_workflow
        # @param [String] step if contains colon :, then the value for workflow and/or workflow/repository. For example: 'jp2-create', 'assemblyWF:jp2-create' or 'dor:assemblyWF:jp2-create'
        # @return [String] workflow:step
        # @example
        #   assemblyWF:jp2-create
        def qualify_step(default_workflow, step)
          current = step.split(':').last(2)
          current.unshift(default_workflow) if current.length < 2
          current.join(':')
        end

        def parse_queued_workflows_response(xml)
          Nokogiri::XML(xml).xpath('/workflows/workflow').collect do |wf_node|
            {
              workflow: wf_node['name'],
              step: wf_node['process'],
              druid: wf_node['druid'],
              lane_id: wf_node['laneId']
            }
          end
        end

        def extract_object_count(resp)
          node = Nokogiri::XML(resp).at_xpath('/objects')
          raise Dor::WorkflowException, 'Unable to determine count from response' if node.nil?

          node['count'].to_i
        end
      end
    end
  end
end
