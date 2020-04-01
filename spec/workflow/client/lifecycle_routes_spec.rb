# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Client::LifecycleRoutes do
  let(:requestor) { instance_double(Dor::Workflow::Client::Requestor, request: response) }
  let(:response) { '<xml />' }
  let(:routes) { described_class.new(requestor: requestor) }
  let(:repo) { 'dor' }
  let(:druid) { 'druid:gv054hp4128' }

  describe '#milestones' do
    let(:ng_xml) { Nokogiri::XML(xml) }
    let(:xml) do
      '<?xml version="1.0" encoding="UTF-8"?><lifecycle objectId="druid:gv054hp4128"><milestone date="2012-01-26T21:06:54-0800" version="2">published</milestone></lifecycle>'
    end

    before do
      allow(routes).to receive(:query_lifecycle).and_return(ng_xml)
      allow(Deprecation).to receive(:warn)
    end

    context 'with positional arguments' do
      subject(:milestones) { routes.milestones(repo, druid) }

      it 'includes the version in with the milestones' do
        expect(milestones.first[:milestone]).to eq('published')
        expect(milestones.first[:version]).to eq('2')
        expect(Deprecation).to have_received(:warn).twice
      end
    end

    context 'with kwargs' do
      subject(:milestones) { routes.milestones(druid: druid) }

      it 'includes the version in with the milestones' do
        expect(milestones.first[:milestone]).to eq('published')
        expect(milestones.first[:version]).to eq('2')
      end
    end
  end

  describe '#lifecycle' do
    context 'with positional arguments' do
      before do
        allow(Deprecation).to receive(:warn)
      end

      context 'without version' do
        subject(:lifecycle) { routes.lifecycle(repo, druid, 'submitted') }

        it 'make the request' do
          lifecycle
          expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle')
          expect(Deprecation).to have_received(:warn).twice
        end
      end

      context 'with version' do
        subject(:lifecycle) { routes.lifecycle(repo, druid, 'submitted', version: 3) }

        it 'makes the request with the version' do
          lifecycle
          expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle?version=3')
          expect(Deprecation).to have_received(:warn).twice
        end
      end
    end

    context 'with kwargs' do
      before do
        allow(Deprecation).to receive(:warn)
      end

      context 'with deprecated repo arg' do
        context 'without version' do
          subject(:lifecycle) { routes.lifecycle(repo: repo, druid: druid, milestone_name: 'submitted') }

          it 'make the request' do
            lifecycle
            expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle')
            expect(Deprecation).to have_received(:warn)
          end
        end

        context 'with version' do
          subject(:lifecycle) { routes.lifecycle(repo: repo, druid: druid, milestone_name: 'submitted', version: 3) }

          it 'makes the request with the version' do
            lifecycle
            expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle?version=3')
            expect(Deprecation).to have_received(:warn)
          end
        end
      end

      context 'without version' do
        subject(:lifecycle) { routes.lifecycle(druid: druid, milestone_name: 'submitted') }

        it 'make the request' do
          lifecycle
          expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle')
          expect(Deprecation).not_to have_received(:warn)
        end
      end

      context 'with version' do
        subject(:lifecycle) { routes.lifecycle(druid: druid, milestone_name: 'submitted', version: 3) }

        it 'makes the request with the version' do
          lifecycle
          expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle?version=3')
          expect(Deprecation).not_to have_received(:warn)
        end
      end
    end
  end

  describe '#active_lifecycle' do
    context 'with positional arguments' do
      before do
        allow(Deprecation).to receive(:warn)
      end

      context 'without version' do
        subject(:active_lifecycle) { routes.active_lifecycle(repo, druid, 'submitted') }

        it 'make the request' do
          active_lifecycle
          expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle?active-only=true')
          expect(Deprecation).to have_received(:warn).twice
        end
      end

      context 'with version' do
        subject(:active_lifecycle) { routes.active_lifecycle(repo, druid, 'submitted', version: 3) }

        it 'makes the request with the version' do
          active_lifecycle
          expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle?version=3&active-only=true')
          expect(Deprecation).to have_received(:warn).twice
        end
      end
    end

    context 'with kwargs' do
      before do
        allow(Deprecation).to receive(:warn)
      end

      context 'with deprecated repo arg' do
        context 'without version' do
          subject(:active_lifecycle) { routes.active_lifecycle(repo: repo, druid: druid, milestone_name: 'submitted') }

          it 'make the request' do
            active_lifecycle
            expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle?active-only=true')
            expect(Deprecation).to have_received(:warn)
          end
        end

        context 'with version' do
          subject(:active_lifecycle) { routes.active_lifecycle(repo: repo, druid: druid, milestone_name: 'submitted', version: 3) }

          it 'makes the request with the version' do
            active_lifecycle
            expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle?version=3&active-only=true')
            expect(Deprecation).to have_received(:warn)
          end
        end
      end

      context 'without version' do
        subject(:active_lifecycle) { routes.active_lifecycle(druid: druid, milestone_name: 'submitted') }

        it 'make the request' do
          active_lifecycle
          expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle?active-only=true')
          expect(Deprecation).not_to have_received(:warn)
        end
      end

      context 'with version' do
        subject(:active_lifecycle) { routes.active_lifecycle(druid: druid, milestone_name: 'submitted', version: 3) }

        it 'makes the request with the version' do
          active_lifecycle
          expect(requestor).to have_received(:request).with('objects/druid:gv054hp4128/lifecycle?version=3&active-only=true')
          expect(Deprecation).not_to have_received(:warn)
        end
      end
    end
  end
end
