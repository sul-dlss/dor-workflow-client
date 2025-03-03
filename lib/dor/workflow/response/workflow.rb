# frozen_string_literal: true

module Dor
  module Workflow
    module Response
      # The response from asking the server about a workflow for an item
      class Workflow
        def initialize(xml:)
          @xml = xml
        end

        def pid
          workflow['objectId']
        end

        def workflow_name
          workflow['id']
        end

        # Check if there are any processes for the provided version.
        # @param [Integer] version the version we are checking for.
        def active_for?(version:)
          result = ng_xml.at_xpath("/workflow/process[@version=#{version}]")
          result ? true : false # rubocop:disable Style/RedundantCondition
        end

        # Returns the process, for the most recent version that matches the given name:
        def process_for_recent_version(name:)
          nodes = process_nodes_for(name: name)
          node = nodes.max { |a, b| a.attr('version').to_i <=> b.attr('version').to_i }
          to_process(node)
        end

        def empty?
          ng_xml.xpath('/workflow/process').empty?
        end

        # Check if all processes are skipped or complete for the provided version.
        # @param [Integer] version the version we are checking for.
        def complete_for?(version:)
          # ng_xml.xpath("/workflow/process[@version=#{version}]/@status").map(&:value).all? { |p| %w[skipped completed].include?(p) }
          incomplete_processes_for(version: version).empty?
        end

        def complete?
          complete_for?(version: version)
        end

        def incomplete_processes_for(version:)
          process_nodes = ng_xml.xpath("/workflow/process[@version=#{version}]")
          incomplete_process_nodes = process_nodes.reject { |process_node| %w[skipped completed].include?(process_node.attr('status')) }
          incomplete_process_nodes.map { |process_node| to_process(process_node) }
        end

        def incomplete_processes
          incomplete_processes_for(version: version)
        end

        attr_reader :xml

        private

        # Return the max version in this workflow document
        def version
          ng_xml.xpath('/workflow/process/@version').map { |attr| attr.value.to_i }.max
        end

        def workflow
          ng_xml.at_xpath('workflow')
        end

        def process_nodes_for(name:)
          ng_xml.xpath("/workflow/process[@name = '#{name}']")
        end

        def ng_xml
          @ng_xml ||= Nokogiri::XML(@xml)
        end

        def to_process(node)
          attributes = node ? node.attributes.to_h { |k, v| [k.to_sym, v.value] } : {}
          Process.new(parent: self, **attributes)
        end
      end
    end
  end
end
