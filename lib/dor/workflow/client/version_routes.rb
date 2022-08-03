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
        def close_version(druid:, version:, create_accession_wf: true)
          requestor.request(construct_url(druid, version, create_accession_wf), 'post', '')
          true
        end

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
