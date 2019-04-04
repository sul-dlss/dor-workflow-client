# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext'
require 'nokogiri'
require 'retries'
require 'dor/workflow_exception'
require 'dor/models/response/workflow'
require 'dor/models/response/update'

require 'dor/workflow/client/connection_factory'
require 'dor/workflow/client/requestor'
require 'dor/workflow/client/queues'
require 'dor/workflow/client/workflow_routes'

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

        @requestor = Requestor.new(connection: connection || ConnectionFactory.build_connection(url, timeout: timeout),
                                   logger: logger)
      end

      delegate :create_workflow, :update_workflow_status, :workflow_status, :workflow_xml,
               :update_workflow_error_status, :all_workflows_xml, :workflows,
               :workflow, :delete_workflow, to: :workflow_routes

      # Returns the Date for a requested milestone from workflow lifecycle
      # @param [String] repo repository name
      # @param [String] druid object id
      # @param [String] milestone name of the milestone being queried for
      # @return [Time] when the milestone was achieved.  Returns nil if the milestone does not exist
      # @example An example lifecycle xml from the workflow service.
      #   <lifecycle objectId="druid:ct011cv6501">
      #     <milestone date="2010-04-27T11:34:17-0700">registered</milestone>
      #     <milestone date="2010-04-29T10:12:51-0700">inprocess</milestone>
      #     <milestone date="2010-06-15T16:08:58-0700">released</milestone>
      #   </lifecycle>
      def lifecycle(repo, druid, milestone)
        doc = query_lifecycle(repo, druid)
        milestone = doc.at_xpath("//lifecycle/milestone[text() = '#{milestone}']")
        return Time.parse(milestone['date']) if milestone

        nil
      end

      # Returns the Date for a requested milestone ONLY FROM THE ACTIVE workflow table
      # @param [String] repo repository name
      # @param [String] druid object id
      # @param [String] milestone name of the milestone being queried for
      # @return [Time] when the milestone was achieved.  Returns nil if the milestone does not exist
      # @example An example lifecycle xml from the workflow service.
      #   <lifecycle objectId="druid:ct011cv6501">
      #     <milestone date="2010-04-27T11:34:17-0700">registered</milestone>
      #     <milestone date="2010-04-29T10:12:51-0700">inprocess</milestone>
      #     <milestone date="2010-06-15T16:08:58-0700">released</milestone>
      #   </lifecycle>
      def active_lifecycle(repo, druid, milestone)
        doc = query_lifecycle(repo, druid, true)
        milestone = doc.at_xpath("//lifecycle/milestone[text() = '#{milestone}']")
        return Time.parse(milestone['date']) if milestone

        nil
      end

      # @return [Hash]
      def milestones(repo, druid)
        doc = query_lifecycle(repo, druid)
        doc.xpath('//lifecycle/milestone').collect do |node|
          { milestone: node.text, at: Time.parse(node['date']), version: node['version'] }
        end
      end

      # @return [Nokogiri::XML::Document]
      def query_lifecycle(repo, druid, active_only = false)
        req = "#{repo}/objects/#{druid}/lifecycle"
        req += '?active-only=true' if active_only
        Nokogiri::XML(requestor.request(req))
      end

      # Calls the versionClose endpoint of the workflow service:
      #
      # - completes the versioningWF:submit-version and versioningWF:start-accession steps
      # - initiates accesssionWF
      #
      # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
      # @param [String] druid The id of the object to delete the workflow from
      # @param [Boolean] create_accession_wf Option to create accessionWF when closing a version.  Defaults to true
      def close_version(repo, druid, create_accession_wf = true)
        uri = "#{repo}/objects/#{druid}/versionClose"
        uri += '?create-accession=false' unless create_accession_wf
        requestor.request(uri, 'post', '')
        true
      end

      def queues
        @queues ||= Queues.new(requestor: requestor)
      end

      def workflow_routes
        @workflow_routes ||= WorkflowRoutes.new(requestor: requestor)
      end

      delegate :lane_ids, :stale_queued_workflows, :count_stale_queued_workflows,
               :objects_for_workstep, :errored_objects_for_workstep, :count_objects_in_step,
               :count_errored_for_workstep, :count_queued_for_workstep,
               to: :queues

      private

      # Among other things, a distinct method helps tests mock default logger
      # @return [Logger] default logger object
      def default_logger
        Logger.new('workflow_service.log', 'weekly')
      end
    end
  end
end
