# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext'
require 'nokogiri'
require 'zeitwerk'

loader = Zeitwerk::Loader.new
root_file = File.absolute_path("#{__FILE__}/../../..")
loader.inflector = Zeitwerk::GemInflector.new(root_file)
loader.push_dir(root_file)
loader.setup

module Dor
  module Workflow
    # TODO: VALID_STATUS should be just another attribute w/ default
    #
    # Create and update workflows
    class Client
      # From Workflow Service's admin/Process.java
      VALID_STATUS = %w[waiting completed error queued skipped hold].freeze

      attr_accessor :requestor

      # Configure the workflow service
      # @param [String] :url points to the workflow service
      # @param [Logger] :logger defaults writing to workflow_service.log with weekly rotation
      # @param [Integer] :timeout number of seconds for HTTP timeout
      # @param [Faraday::Connection] :connection the REST client resource
      def initialize(url: nil, logger: default_logger, timeout: nil, connection: nil)
        raise ArgumentError, 'You must provide either a connection or a url' if !url && !connection

        @requestor = Requestor.new(connection: connection || ConnectionFactory.build_connection(url, timeout: timeout, logger: logger))
      end

      delegate :create_workflow, :create_workflow_by_name, :update_workflow_status, :workflow_status,
               :workflow_xml, :update_workflow_error_status, :all_workflows_xml, :workflows,
               :workflow, :delete_workflow, :delete_all_workflows, to: :workflow_routes

      delegate :lifecycle, :active_lifecycle, :milestones, to: :lifecycle_routes

      delegate :lane_ids, :stale_queued_workflows, :count_stale_queued_workflows,
               :objects_for_workstep, :errored_objects_for_workstep, :count_objects_in_step,
               :count_errored_for_workstep, :count_queued_for_workstep,
               to: :queues

      delegate :close_version, to: :version_routes

      def queues
        @queues ||= Queues.new(requestor: requestor)
      end

      def workflow_routes
        @workflow_routes ||= WorkflowRoutes.new(requestor: requestor)
      end

      def lifecycle_routes
        @lifecycle_routes ||= LifecycleRoutes.new(requestor: requestor)
      end

      def version_routes
        @version_routes ||= VersionRoutes.new(requestor: requestor)
      end

      private

      # Among other things, a distinct method helps tests mock default logger
      # @return [Logger] default logger object
      def default_logger
        Logger.new('workflow_service.log', 'weekly')
      end
    end
  end
end
