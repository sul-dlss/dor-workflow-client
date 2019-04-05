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
        def close_version(repo, druid, create_accession_wf = true)
          uri = "#{repo}/objects/#{druid}/versionClose"
          uri += '?create-accession=false' unless create_accession_wf
          requestor.request(uri, 'post', '')
          true
        end

        private

        attr_reader :requestor
      end
    end
  end
end
