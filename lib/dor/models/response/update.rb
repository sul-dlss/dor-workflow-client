# frozen_string_literal: true

require 'dor/models/response/process'

module Dor
  module Workflow
    module Response
      # The response from telling the server to update a workflow step.
      class Update
        def initialize(json:)
          @json = JSON.parse(json)
        end

        def next_steps
          @json[:next_steps]
        end
      end
    end
  end
end
