# frozen_string_literal: true

module Dor
  module Workflow
    module Response
      # The response form asking the server about a workflow for an item
      class Workflow
        def initialize(xml:)
          @xml = xml
        end

        # @param [Integer] version the version we are checking for.
        def active_for?(version:)
          result = ng_xml.at_xpath("/workflow/process[@version=#{version}]")
          result ? true : false
        end

        private

        def ng_xml
          @ng_xml ||= Nokogiri::XML(@xml)
        end
      end
    end
  end
end
