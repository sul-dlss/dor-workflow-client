# frozen_string_literal: true

module Dor
  module Workflow
    class Client
      # Makes requests relating to versions
      class VersionRoutes
        def initialize(requestor:)
          @requestor = requestor
        end

        # Calls the versionClose endpoint of the workflow service:
        #
        # - completes the versioningWF:submit-version and versioningWF:start-accession steps
        # - initiates accesssionWF
        #
        # @param [String] repo The repository the object resides in. This parameter is deprecated
        # @param [String] druid The id of the object to delete the workflow from
        # @param [Boolean] create_accession_wf Option to create accessionWF when closing a version.  Defaults to true
        # rubocop:disable Metrics/MethodLength
        def close_version(*args)
          case args.size
          when 3
            Deprecation.warn(self, 'you provided 3 args, but close_version now takes kwargs')
            (repo, druid, create_accession_wf) = args
          when 2
            Deprecation.warn(self, 'you provided 2 args, but close_version now takes kwargs')
            (repo, druid) = args
            create_accession_wf = true
          when 1
            opts = args.first
            repo = opts[:repo]
            druid = opts[:druid]
            version = opts[:version]
            create_accession_wf = opts.key?(:create_accession_wf) ? opts[:create_accession_wf] : true
          else
            raise ArgumentError, 'wrong number of arguments, must be 1-3'
          end

          Deprecation.warn(self, 'passing the repo parameter to close_version is no longer necessary. This will raise an error in dor-workflow-client version 4') if repo

          requestor.request(construct_url(druid, version, create_accession_wf), 'post', '')
          true
        end
        # rubocop:enable Metrics/MethodLength

        private

        attr_reader :requestor

        def construct_url(druid, version, create_accession_wf)
          url = "objects/#{druid}/versionClose"

          qs_args = []
          qs_args << "version=#{version}" if version
          qs_args << 'create-accession=false' unless create_accession_wf
          url += "?#{qs_args.join('&')}" unless qs_args.empty?
          url
        end
      end
    end
  end
end
