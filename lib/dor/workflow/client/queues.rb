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
        # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
        # @param [String] workflow name
        # @param [String] process name
        # @return [Array<String>] all of the distinct laneIds.  Array will be empty if no lane ids were found
        def lane_ids(repo, workflow, process)
          uri = "workflow_queue/lane_ids?step=#{repo}:#{workflow}:#{process}"
          doc = Nokogiri::XML(requestor.request(uri))
          nodes = doc.xpath('/lanes/lane')
          nodes.map { |n| n['id'] }
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
        def stale_queued_workflows(repository, opts = {})
          uri_string = build_queued_uri(repository, opts)
          parse_queued_workflows_response requestor.request(uri_string)
        end

        # Returns a count of workflow steps that have a status of 'queued' that have a last-updated timestamp older than the number of hours passed in
        # @param [String] repository name of the repository you want to query, like 'dor' or 'sdr'
        # @param [Hash] opts optional values for query
        # @option opts [Integer] :hours_ago steps older than this value will be returned by the query.  If not passed in, the service defaults to 0 hours,
        #   meaning you will get all queued workflows
        # @return [Integer] number of stale, queued steps if the :count_only option was set to true
        def count_stale_queued_workflows(repository, opts = {})
          uri_string = build_queued_uri(repository, opts) + '&count-only=true'
          doc = Nokogiri::XML(requestor.request(uri_string))
          doc.at_xpath('/objects/@count').value.to_i
        end

        # Returns a list of druids from the workflow service that meet the criteria
        # of the passed in completed and waiting params
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
          waiting_param = qualify_step(options[:default_repository], options[:default_workflow], waiting)
          uri_string = "workflow_queue?waiting=#{waiting_param}"
          if completed
            Array(completed).each do |step|
              completed_param = qualify_step(options[:default_repository], options[:default_workflow], step)
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
        #     client.errored_objects_for_workstep('accessionWF','content-metadata')
        #     => {"druid:qd556jq0580"=>"druid:qd556jq0580 - Item error; caused by
        #        #<Rubydora::FedoraInvalidRequest: Error modifying datastream contentMetadata for druid:qd556jq0580. See logger for details>"}
        def errored_objects_for_workstep(workflow, step, repository = 'dor')
          resp = requestor.request "workflow_queue?repository=#{repository}&workflow=#{workflow}&error=#{step}"
          result = {}
          Nokogiri::XML(resp).xpath('//object').collect do |node|
            result.merge!(node['id'] => node['errorMessage'])
          end
          result
        end

        def count_objects_in_step(workflow, step, type, repo)
          resp = requestor.request "workflow_queue?repository=#{repo}&workflow=#{workflow}&#{type}=#{step}"
          extract_object_count(resp)
        end

        private

        attr_reader :requestor

        def build_queued_uri(repository, opts = {})
          uri_string = "workflow_queue/all_queued?repository=#{repository}"
          uri_string += "&hours-ago=#{opts[:hours_ago]}" if opts[:hours_ago]
          uri_string += "&limit=#{opts[:limit]}"         if opts[:limit]
          uri_string
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

        def parse_queued_workflows_response(xml)
          doc = Nokogiri::XML(xml)
          doc.xpath('/workflows/workflow').collect do |wf_node|
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
