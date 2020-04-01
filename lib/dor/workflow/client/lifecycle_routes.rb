# frozen_string_literal: true

# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
module Dor
  module Workflow
    class Client
      # Makes requests relating to a lifecycle
      class LifecycleRoutes
        def initialize(requestor:)
          @requestor = requestor
        end

        # Returns the Date for a requested milestone from workflow lifecycle
        #
        # @param [String] repo The repository the object resides in. This parameter is deprecated
        # @param [String] druid object id
        # @param [String] milestone_name the name of the milestone being queried for
        # @param [Number] version the version to query for
        # @param [Boolean] active_only (false) if true, return only lifecycle steps for versions that have all processes complete
        # @return [Time] when the milestone was achieved.  Returns nil if the milestone does not exist
        #
        def lifecycle(*args)
          case args.size
          when 5
            Deprecation.warn(self, 'you provided 5 args, but lifecycle now takes kwargs')
            (repo, druid, milestone_name) = args[0..2]
            version = args[3][:version]
            active_only = args[4][:active_only]
          when 4
            Deprecation.warn(self, 'you provided 4 args, but lifecycle now takes kwargs')
            (repo, druid, milestone_name) = args[0..2]
            version = args[3][:version]
            active_only = false
          when 3
            Deprecation.warn(self, 'you provided 3 args, but lifecycle now takes kwargs')
            (repo, druid, milestone_name) = args
            version = nil
            active_only = false
          when 2
            Deprecation.warn(self, 'you provided 2 args, but lifecycle now takes kwargs')
            (druid, milestone_name) = args
            version = nil
            active_only = false
          when 1
            opts = args.first
            repo = opts[:repo]
            druid = opts[:druid]
            milestone_name = opts[:milestone_name]
            version = opts[:version]
            active_only = opts.key?(:active_only) ? opts[:active_only] : false
          else
            raise ArgumentError, 'wrong number of arguments, must be 1-5'
          end

          Deprecation.warn(self, 'passing the repo parameter to lifecycle is no longer necessary. This will raise an error in dor-workflow-client version 4') if repo

          filter_milestone(query_lifecycle(druid, version: version, active_only: active_only), milestone_name)
        end

        # Returns the Date for a requested milestone ONLY for the current version.
        # This is slow as the workflow server will query dor-services-app for the version.
        # A better approach is #lifecycle with the version tag.
        # @param [String] druid object id
        # @param [String] milestone_name the name of the milestone being queried for
        # @param [Number] version the version to query for
        # @return [Time] when the milestone was achieved.  Returns nil if the milestone does not exis
        #
        def active_lifecycle(*args)
          case args.size
          when 4
            Deprecation.warn(self, 'you provided 4 args, but active_lifecycle now takes kwargs')
            (repo, druid, milestone_name) = args[0..2]
            version = args[3][:version]
          when 3
            Deprecation.warn(self, 'you provided 3 args, but active_lifecycle now takes kwargs')
            (repo, druid, milestone_name) = args
            version = nil
          when 2
            Deprecation.warn(self, 'you provided 2 args, but active_lifecycle now takes kwargs')
            (druid, milestone_name) = args
            version = nil
          when 1
            opts = args.first
            repo = opts[:repo]
            druid = opts[:druid]
            milestone_name = opts[:milestone_name]
            version = opts[:version]
          else
            raise ArgumentError, 'wrong number of arguments, must be 1-4'
          end

          Deprecation.warn(self, 'passing the repo parameter to active_lifecycle is no longer necessary. This will raise an error in dor-workflow-client version 4') if repo

          lifecycle(druid: druid, milestone_name: milestone_name, version: version, active_only: true)
        end

        # @return [Array<Hash>]
        def milestones(*args)
          case args.size
          when 2
            Deprecation.warn(self, 'you provided 2 args, but active_lifecycle now takes kwargs')
            (repo, druid) = args
          when 1
            opts = args.first
            repo = opts[:repo]
            druid = opts[:druid]
          else
            raise ArgumentError, 'wrong number of arguments, must be 1-2'
          end

          Deprecation.warn(self, 'passing the repo parameter to active_lifecycle is no longer necessary. This will raise an error in dor-workflow-client version 4') if repo

          doc = query_lifecycle(druid, active_only: false)
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

        # @param [String] druid object id
        # @param [Boolean] active_only (false) if true, return only lifecycle steps for versions that have all processes complete
        # @param [Number] version the version to query for
        # @return [Nokogiri::XML::Document]
        # @example An example lifecycle xml from the workflow service.
        #   <lifecycle objectId="druid:ct011cv6501">
        #     <milestone date="2010-04-27T11:34:17-0700">registered</milestone>
        #     <milestone date="2010-04-29T10:12:51-0700">inprocess</milestone>
        #     <milestone date="2010-06-15T16:08:58-0700">released</milestone>
        #   </lifecycle>
        #
        def query_lifecycle(druid, active_only:, version: nil)
          req = "objects/#{druid}/lifecycle"
          params = []
          params << "version=#{version}" if version
          params << 'active-only=true' if active_only
          req += "?#{params.join('&')}" unless params.empty?

          Nokogiri::XML(requestor.request(req))
        end

        attr_reader :requestor
      end
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
