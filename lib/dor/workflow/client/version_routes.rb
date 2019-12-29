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
        # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
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
            create_accession_wf = opts.key?(:create_accession_wf) ? opts[:create_accession_wf] : true
          else
            raise ArgumentError, 'wrong number of arguments, must be 1-3'
          end

          uri = "#{repo}/objects/#{druid}/versionClose"
          uri += '?create-accession=false' unless create_accession_wf
          requestor.request(uri, 'post', '')
          true
        end
        # rubocop:enable Metrics/MethodLength

        private

        attr_reader :requestor
      end
    end
  end
end
