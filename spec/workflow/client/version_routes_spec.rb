# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Client::VersionRoutes do
  let(:mock_requestor) { instance_double(Dor::Workflow::Client::Requestor, request: nil) }

  let(:routes) { described_class.new(requestor: mock_requestor) }

  let(:repo) { 'dor' }

  let(:druid) { 'druid:123' }

  describe '#close_version' do
    context 'with kwargs' do
      it 'passes version' do
        routes.close_version(druid: druid, version: 3)
        expect(mock_requestor).to have_received(:request)
          .with('objects/druid:123/versionClose?version=3', 'post', '')
      end

      it 'optionally prevents creation of accessionWF and passes version' do
        routes.close_version(druid: druid, create_accession_wf: false, version: 3)
        expect(mock_requestor).to have_received(:request)
          .with('objects/druid:123/versionClose?version=3&create-accession=false', 'post', '')
      end
    end
  end
end
