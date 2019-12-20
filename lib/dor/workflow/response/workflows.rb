# frozen_string_literal: true

module Dor
  module Workflow
    module Response
      # The response from asking the server about all workflows for an item
      class Workflows
        def initialize(xml:)
          @xml = xml
        end

        def pid
          ng_xml.at_xpath('/workflows/@objectId').text
        end

        def workflows
          @workflows ||= ng_xml.xpath('/workflows/workflow').map do |node|
            Workflow.new(xml: node.to_xml)
          end
        end

        # @return [Array<String>] returns a list of errors for any process for the current version
        def errors_for(version:)
          ng_xml.xpath("//workflow/process[@version='#{version}' and @status='error']/@errorMessage")
                .map(&:text)
        end

        attr_reader :xml

        private

        def ng_xml
          @ng_xml ||= Nokogiri::XML(@xml)
        end
      end
    end
  end
end
