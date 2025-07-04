# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext'
require 'nokogiri'
require 'zeitwerk'
require 'faraday'
require 'faraday/retry'
require 'deprecation'

loader = Zeitwerk::Loader.new
# Zeitwerk::GemInflector wants to be instantiated with the main .rb entrypoint
# into a gem, which is this file.
loader.inflector = Zeitwerk::GemInflector.new(__FILE__)
# `#push_dir`, on the other hand, wants to be pointed at the dir that holds your
# root namespace directory, which for dor-workflow-client is the `lib/`
# directory. Our root namespace is `Dor::` which lives in `lib/dor/`
loader.push_dir(File.absolute_path("#{__FILE__}/../../.."))
loader.setup

module Dor
  module Workflow
    # TODO: VALID_STATUS should be just another attribute w/ default
    #
    # Create and update workflows
    class Client
      # From workflow-server-rails' app/models/workflow_step.rb
      VALID_STATUS = %w[waiting completed error queued skipped started retrying].freeze

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

      delegate :create_workflow_by_name, :workflow_status, :workflows, :all_workflows, :skip_all,
               :workflow, :process, :delete_workflow, :delete_all_workflows, :update_status, :update_error_status,
               to: :workflow_routes

      delegate :lifecycle, :active_lifecycle, :milestones, :query_lifecycle, to: :lifecycle_routes

      delegate :lane_ids, :objects_for_workstep, :objects_erroring_at_workstep, to: :queues

      def queues
        @queues ||= Queues.new(requestor: requestor)
      end

      def workflow_routes
        @workflow_routes ||= WorkflowRoutes.new(requestor: requestor)
      end

      def lifecycle_routes
        @lifecycle_routes ||= LifecycleRoutes.new(requestor: requestor)
      end

      def workflow_template(name)
        templates.retrieve(name)
      end

      def workflow_templates
        templates.all
      end

      def templates
        WorkflowTemplate.new(requestor: requestor)
      end

      def status(druid:, version:)
        Status.new(druid: druid, version: version, lifecycle_routes: lifecycle_routes)
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
