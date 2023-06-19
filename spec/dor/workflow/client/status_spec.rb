# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Client::Status do
  subject(:instance) do
    described_class.new(druid: druid, version: version, lifecycle_routes: lifecycle_routes)
  end

  let(:druid) { 'druid:ab123cd4567' }
  let(:version) { '2' }
  let(:lifecycle_routes) { Dor::Workflow::Client::LifecycleRoutes.new(requestor: requestor) }
  let(:requestor) { instance_double(Dor::Workflow::Client::Requestor, request: xml) }

  describe '#display' do
    subject(:status) { instance.display }

    describe 'for gv054hp4128' do
      context 'when current version is published, but does not have a version attribute' do
        let(:xml) do
          '<?xml version="1.0" encoding="UTF-8"?>
          <lifecycle objectId="druid:gv054hp4128">
          <milestone date="2012-11-06T16:19:15-0800" version="2">described</milestone>
          <milestone date="2012-11-06T16:21:02-0800">opened</milestone>
          <milestone date="2012-11-06T16:30:03-0800">submitted</milestone>
          <milestone date="2012-11-06T16:35:00-0800">described</milestone>
          <milestone date="2012-11-06T16:59:39-0800" version="3">published</milestone>
          <milestone date="2012-11-06T16:59:39-0800">published</milestone>
          </lifecycle>'
        end

        let(:version) { '4' }

        it 'generates a status string' do
          expect(status).to eq('v4 In accessioning (described, published)')
        end
      end

      context 'when current version matches the attribute in the milestone' do
        let(:xml) do
          '<?xml version="1.0" encoding="UTF-8"?>
          <lifecycle objectId="druid:gv054hp4128">
          <milestone date="2012-11-06T16:19:15-0800" version="2">described</milestone>
          <milestone date="2012-11-06T16:59:39-0800" version="3">published</milestone>
          </lifecycle>'
        end
        let(:version) { '3' }

        it 'generates a status string' do
          expect(status).to eq('v3 In accessioning (described, published)')
        end
      end
    end

    describe 'for bd504dj1946' do
      let(:xml) do
        '<?xml version="1.0"?>
        <lifecycle objectId="druid:bd504dj1946">
        <milestone date="2013-04-03T15:01:57-0700">registered</milestone>
        <milestone date="2013-04-03T16:20:19-0700">digitized</milestone>
        <milestone date="2013-04-16T14:18:20-0700" version="1">submitted</milestone>
        <milestone date="2013-04-16T14:32:54-0700" version="1">described</milestone>
        <milestone date="2013-04-16T14:55:10-0700" version="1">published</milestone>
        <milestone date="2013-07-21T05:27:23-0700" version="1">deposited</milestone>
        <milestone date="2013-07-21T05:28:09-0700" version="1">accessioned</milestone>
        <milestone date="2013-08-15T11:59:16-0700" version="2">opened</milestone>
        <milestone date="2013-10-01T12:01:07-0700" version="2">submitted</milestone>
        <milestone date="2013-10-01T12:01:24-0700" version="2">described</milestone>
        <milestone date="2013-10-01T12:05:38-0700" version="2">published</milestone>
        <milestone date="2013-10-01T12:10:56-0700" version="2">deposited</milestone>
        <milestone date="2013-10-01T12:11:10-0700" version="2">accessioned</milestone>
        </lifecycle>'
      end

      it 'handles a v2 accessioned object' do
        expect(status).to eq('v2 Accessioned')
      end

      context 'when version is an integer' do
        let(:version) { 2 }

        it 'converts to a string' do
          expect(status).to eq('v2 Accessioned')
        end
      end

      context 'when there are no lifecycles for the current version, indicating malfunction in workflow' do
        let(:version) { '3' }

        it 'gives a status of unknown' do
          expect(status).to eq('v3 Unknown Status')
        end
      end

      context 'when time is requested' do
        subject(:status) { instance.display(include_time: true) }

        it 'includes a formatted date/time if one is requested' do
          expect(status).to eq('v2 Accessioned 2013-10-01 07:11PM')
        end
      end
    end

    context 'with an accessioned step with the exact same timestamp as the deposited step' do
      subject(:status) { instance.display(include_time: true) }

      let(:xml) do
        '<?xml version="1.0"?>
        <lifecycle objectId="druid:bd504dj1946">
        <milestone date="2013-04-03T15:01:57-0700">registered</milestone>
        <milestone date="2013-04-03T16:20:19-0700">digitized</milestone>
        <milestone date="2013-04-16T14:18:20-0700" version="1">submitted</milestone>
        <milestone date="2013-04-16T14:32:54-0700" version="1">described</milestone>
        <milestone date="2013-04-16T14:55:10-0700" version="1">published</milestone>
        <milestone date="2013-07-21T05:27:23-0700" version="1">deposited</milestone>
        <milestone date="2013-07-21T05:28:09-0700" version="1">accessioned</milestone>
        <milestone date="2013-08-15T11:59:16-0700" version="2">opened</milestone>
        <milestone date="2013-10-01T12:01:07-0700" version="2">submitted</milestone>
        <milestone date="2013-10-01T12:01:24-0700" version="2">described</milestone>
        <milestone date="2013-10-01T12:05:38-0700" version="2">published</milestone>
        <milestone date="2013-10-01T12:10:56-0700" version="2">deposited</milestone>
        <milestone date="2013-10-01T12:10:56-0700" version="2">accessioned</milestone>
        </lifecycle>'
      end

      it 'has the correct status of accessioned (v2) object' do
        expect(status).to eq('v2 Accessioned 2013-10-01 07:10PM')
      end
    end

    context 'with an accessioned step with an ealier timestamp than the deposited step' do
      subject(:status) { instance.display(include_time: true) }

      let(:xml) do
        '<?xml version="1.0"?>
        <lifecycle objectId="druid:bd504dj1946">
        <milestone date="2013-04-03T15:01:57-0700">registered</milestone>
        <milestone date="2013-04-03T16:20:19-0700">digitized</milestone>
        <milestone date="2013-04-16T14:18:20-0700" version="1">submitted</milestone>
        <milestone date="2013-04-16T14:32:54-0700" version="1">described</milestone>
        <milestone date="2013-04-16T14:55:10-0700" version="1">published</milestone>
        <milestone date="2013-07-21T05:27:23-0700" version="1">deposited</milestone>
        <milestone date="2013-07-21T05:28:09-0700" version="1">accessioned</milestone>
        <milestone date="2013-08-15T11:59:16-0700" version="2">opened</milestone>
        <milestone date="2013-10-01T12:01:07-0700" version="2">submitted</milestone>
        <milestone date="2013-10-01T12:01:24-0700" version="2">described</milestone>
        <milestone date="2013-10-01T12:05:38-0700" version="2">published</milestone>
        <milestone date="2013-10-01T12:10:56-0700" version="2">deposited</milestone>
        <milestone date="2013-09-01T12:10:56-0700" version="2">accessioned</milestone>
        </lifecycle>'
      end

      it 'has the correct status of accessioned (v2) object' do
        expect(status).to eq('v2 Accessioned 2013-09-01 07:10PM')
      end
    end

    context 'with a deposited step for a non-accessioned object' do
      subject(:status) { instance.display(include_time: true) }

      let(:xml) do
        '<?xml version="1.0"?>
        <lifecycle objectId="druid:bd504dj1946">
        <milestone date="2013-04-03T15:01:57-0700">registered</milestone>
        <milestone date="2013-04-03T16:20:19-0700">digitized</milestone>
        <milestone date="2013-04-16T14:18:20-0700" version="1">submitted</milestone>
        <milestone date="2013-04-16T14:32:54-0700" version="1">described</milestone>
        <milestone date="2013-04-16T14:55:10-0700" version="1">published</milestone>
        <milestone date="2013-07-21T05:27:23-0700" version="1">deposited</milestone>
        <milestone date="2013-07-21T05:28:09-0700" version="1">accessioned</milestone>
        <milestone date="2013-08-15T11:59:16-0700" version="2">opened</milestone>
        <milestone date="2013-10-01T12:01:07-0700" version="2">submitted</milestone>
        <milestone date="2013-10-01T12:01:24-0700" version="2">described</milestone>
        <milestone date="2013-10-01T12:05:38-0700" version="2">published</milestone>
        <milestone date="2013-10-01T12:10:56-0700" version="2">deposited</milestone>
        </lifecycle>'
      end

      it 'has the correct status of deposited (v2) object' do
        expect(status).to eq('v2 In accessioning (described, published, deposited) 2013-10-01 07:10PM')
      end
    end
  end

  describe '#display_simplified' do
    subject(:status) { instance.display_simplified }

    let(:xml) do
      '<?xml version="1.0" encoding="UTF-8"?>
      <lifecycle objectId="druid:gv054hp4128">
      <milestone date="2012-11-06T16:19:15-0800" version="2">described</milestone>
      <milestone date="2012-11-06T16:21:02-0800">opened</milestone>
      <milestone date="2012-11-06T16:30:03-0800">submitted</milestone>
      <milestone date="2012-11-06T16:35:00-0800">described</milestone>
      <milestone date="2012-11-06T16:59:39-0800" version="3">published</milestone>
      <milestone date="2012-11-06T16:59:39-0800">published</milestone>
      </lifecycle>'
    end

    it 'generates a status string' do
      expect(status).to eq('In accessioning')
    end
  end
end
