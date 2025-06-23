# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Client::LifecycleRoutes do
  let(:requestor) { instance_double(Dor::Workflow::Client::Requestor, request: response) }
  let(:response) { '<xml />' }
  let(:routes) { described_class.new(requestor: requestor) }
  let(:repo) { 'dor' }
  let(:druid) { 'druid:gv054hp4128' }

  describe '#milestones' do
    subject(:milestones) { routes.milestones(druid: druid) }

    let(:ng_xml) { Nokogiri::XML(xml) }
    let(:xml) do
      '<?xml version="1.0" encoding="UTF-8"?><lifecycle objectId="druid:gv054hp4128"><milestone date="2012-01-26T21:06:54-0800" version="2">published</milestone></lifecycle>'
    end

    before do
      allow(routes).to receive(:query_lifecycle).and_return(ng_xml)
    end

    it 'includes the version in with the milestones' do
      expect(milestones.first[:milestone]).to eq('published')
      expect(milestones.first[:version]).to eq('2')
    end
  end

  describe '#lifecycle' do
    context 'without version' do
      subject(:lifecycle) { routes.lifecycle(druid: druid, milestone_name: 'submitted') }

      it 'make the request' do
        lifecycle
        expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle')
      end
    end

    context 'with version' do
      subject(:lifecycle) { routes.lifecycle(druid: druid, milestone_name: 'submitted', version: 3) }

      it 'makes the request with the version' do
        lifecycle
        expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle?version=3')
      end
    end
  end

  describe '#active_lifecycle' do
    context 'with kwargs' do
      subject(:active_lifecycle) { routes.active_lifecycle(druid: druid, milestone_name: 'submitted', version: 3) }

      it 'makes the request with the version' do
        active_lifecycle
        expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle?version=3&active-only=true')
      end
    end
  end

  describe '#query_lifecycle' do
    subject(:lifecycle) { routes.query_lifecycle(druid, active_only: true, version: 2) }

    let(:xml) do
      '<?xml version="1.0" encoding="UTF-8"?><lifecycle objectId="druid:gv054hp4128"><milestone date="2012-01-26T21:06:54-0800" version="2">published</milestone></lifecycle>'
    end

    before do
      allow(requestor).to receive(:request).and_return(xml)
    end

    it 'returns XML' do
      expect(lifecycle).to be_a(Nokogiri::XML::Document)
      expect(lifecycle.to_xml).to eq(Nokogiri::XML(xml).to_xml)

      expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle?version=2&active-only=true')
    end
  end
end
