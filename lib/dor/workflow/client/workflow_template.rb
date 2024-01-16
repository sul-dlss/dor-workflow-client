# frozen_string_literal: true

module Dor
  module Workflow
    class Client
      # Makes requests relating to a workflow template
      class WorkflowTemplate
        def initialize(requestor:)
          @requestor = requestor
        end

        # Retrieves a representation of the workflow template
        #
        # @param [String] workflow_name The name of the workflow you want to retrieve
        # @return [Hash] a representation of the workflow template
        # @example:
        #   retrieve('assemblyWF') => '{"processes":[{"name":"start-assembly"},{"name":"content-metadata-create"},...]}'
        #
        def retrieve(workflow_name)
          body = requestor.request "workflow_templates/#{workflow_name}"
          JSON.parse(body)
        end

        # Retrieves a list of workflow template name
        #
        # @return [Array<String>] the list of templates
        #
        def all
          body = requestor.request 'workflow_templates'
          JSON.parse(body)
        end

        private

        attr_reader :requestor
      end
    end
  end
end
