# frozen_string_literal: true

module Dor
  module Workflow
    module Response
      # Represents the status of an object doing a workflow process
      class Process
        extend Deprecation
        self.deprecation_horizon = '4.x'

        # @params [Workflow] parent
        # @params [Hash] attributes
        def initialize(parent:, **attributes)
          @parent = parent
          @attributes = attributes
        end

        def name
          @attributes[:name].presence
        end

        def status
          @attributes[:status].presence
        end

        def datetime
          @attributes[:datetime].presence
        end

        def elapsed
          @attributes[:elapsed].presence
        end

        def attempts
          @attributes[:attempts].presence
        end

        def lifecycle
          @attributes[:lifecycle].presence
        end

        def note
          @attributes[:note].presence
        end

        def error_message
          @attributes[:errorMessage].presence
        end

        def lane_id
          @attributes[:laneId].presence
        end

        # @return [Hash] the context for the process (or empty hash if none present)
        def context
          return {} unless @attributes[:context].present?

          JSON.parse(@attributes[:context])
        end

        delegate :pid, :workflow_name, to: :parent

        private

        attr_reader :parent
      end
    end
  end
end
