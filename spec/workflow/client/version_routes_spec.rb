# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Client::VersionRoutes do
  let(:mock_requestor) { instance_double(Dor::Workflow::Client::Requestor, request: nil) }

  let(:routes) { described_class.new(requestor: mock_requestor) }

  let(:repo) { 'dor' }

  let(:druid) { 'druid:123' }

  describe '#close_version' do
    context 'with positional arguments' do
      before do
        allow(Deprecation).to receive(:warn)
      end

      it 'calls the versionClose endpoint with druid' do
        routes.close_version(repo, druid)
        expect(Deprecation).to have_received(:warn).twice
      end

      it 'optionally prevents creation of accessionWF' do
        routes.close_version(repo, druid, false)
        expect(mock_requestor).to have_received(:request)
          .with('objects/druid:123/versionClose?create-accession=false', 'post', '')
        expect(Deprecation).to have_received(:warn).twice
      end
    end

    context 'with kwargs' do
      it 'calls the versionClose endpoint' do
        routes.close_version(druid: druid)
        expect(mock_requestor).to have_received(:request)
          .with('objects/druid:123/versionClose', 'post', '')
      end

      context 'with deprecated repo arg' do
        before do
          allow(Deprecation).to receive(:warn)
        end

        it 'calls the versionClose endpoint' do
          routes.close_version(repo: repo, druid: druid)
          expect(mock_requestor).to have_received(:request)
            .with('objects/druid:123/versionClose', 'post', '')
          expect(Deprecation).to have_received(:warn)
        end
      end

      it 'optionally prevents creation of accessionWF' do
        routes.close_version(druid: druid, create_accession_wf: false)
        expect(mock_requestor).to have_received(:request)
          .with('objects/druid:123/versionClose?create-accession=false', 'post', '')
      end

      it 'optionally passes version' do
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
