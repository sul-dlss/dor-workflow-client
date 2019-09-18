# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Client::LifecycleRoutes do
  let(:requestor) { instance_double(Dor::Workflow::Client::Requestor, request: response) }
  let(:response) { '<xml />' }
  let(:routes) { described_class.new(requestor: requestor) }

  describe '#milestones' do
    let(:ng_xml) { Nokogiri::XML(xml) }
    let(:xml) do
      '<?xml version="1.0" encoding="UTF-8"?><lifecycle objectId="druid:gv054hp4128"><milestone date="2012-01-26T21:06:54-0800" version="2">published</milestone></lifecycle>'
    end

    before do
      allow(routes).to receive(:query_lifecycle).and_return(ng_xml)
    end

    subject(:milestones) { routes.milestones('dor', 'druid:gv054hp4128') }

    it 'includes the version in with the milestones' do
      expect(milestones.first[:milestone]).to eq('published')
      expect(milestones.first[:version]).to eq('2')
    end
  end

  describe '#lifecycle' do
    context 'without version' do
      subject(:lifecycle) { routes.lifecycle('dor', 'druid:gv054hp4128', 'submitted') }

      it 'make the request' do
        lifecycle
        expect(requestor).to have_received(:request).with('dor/objects/druid:gv054hp4128/lifecycle')
      end
    end

    context 'with version' do
      subject(:lifecycle) { routes.lifecycle('dor', 'druid:gv054hp4128', 'submitted', version: 3) }

      it 'makes the request with the version' do
        lifecycle
        expect(requestor).to have_received(:request).with('dor/objects/druid:gv054hp4128/lifecycle?version=3')
      end
    end
  end
end
