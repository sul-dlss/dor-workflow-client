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
        # @param [String] workflow name
        # @param [String] process name
        # @return [Array<String>] all of the distinct laneIds.  Array will be empty if no lane ids were found
        def lane_ids(workflow, process)
          uri = "workflow_queue/lane_ids?step=#{workflow}:#{process}"
          doc = Nokogiri::XML(requestor.request(uri))
          doc.xpath('/lanes/lane').map { |n| n['id'] }
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

        private

        attr_reader :requestor

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
      end
    end
  end
end
