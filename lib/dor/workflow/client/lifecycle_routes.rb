# frozen_string_literal: true

module Dor
  module Workflow
    class Client
      # Makes requests relating to a lifecycle
      class LifecycleRoutes
        def initialize(requestor:)
          @requestor = requestor
        end

        # Returns the Date for a requested milestone from workflow lifecycle
        # @param [String] repo repository name
        # @param [String] druid object id
        # @param [String] milestone_name the name of the milestone being queried for
        # @return [Time] when the milestone was achieved.  Returns nil if the milestone does not exist
        #
        def lifecycle(repo, druid, milestone_name)
          filter_milestone(query_lifecycle(repo, druid), milestone_name)
        end

        # Returns the Date for a requested milestone ONLY FROM THE ACTIVE workflow table
        # @param [String] repo repository name
        # @param [String] druid object id
        # @param [String] milestone_name the name of the milestone being queried for
        # @return [Time] when the milestone was achieved.  Returns nil if the milestone does not exis
        #
        def active_lifecycle(repo, druid, milestone_name)
          filter_milestone(query_lifecycle(repo, druid, true), milestone_name)
        end

        # @return [Hash]
        def milestones(repo, druid)
          doc = query_lifecycle(repo, druid)
          doc.xpath('//lifecycle/milestone').collect do |node|
            { milestone: node.text, at: Time.parse(node['date']), version: node['version'] }
          end
        end

        private

        def filter_milestone(lifecycle_doc, milestone_name)
          milestone = lifecycle_doc.at_xpath("//lifecycle/milestone[text() = '#{milestone_name}']")
          return unless milestone

          Time.parse(milestone['date'])
        end

        # @return [Nokogiri::XML::Document]
        # @example An example lifecycle xml from the workflow service.
        #   <lifecycle objectId="druid:ct011cv6501">
        #     <milestone date="2010-04-27T11:34:17-0700">registered</milestone>
        #     <milestone date="2010-04-29T10:12:51-0700">inprocess</milestone>
        #     <milestone date="2010-06-15T16:08:58-0700">released</milestone>
        #   </lifecycle>
        #
        def query_lifecycle(repo, druid, active_only = false)
          req = "#{repo}/objects/#{druid}/lifecycle"
          req += '?active-only=true' if active_only
          Nokogiri::XML(requestor.request(req))
        end

        attr_reader :requestor
      end
    end
  end
end
