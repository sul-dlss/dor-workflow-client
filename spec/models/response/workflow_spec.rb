# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Response::Workflow do
  subject(:instance) { described_class.new(xml: xml) }

  describe '#pid' do
    subject { instance.pid }

    let(:xml) do
      <<~XML
        <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
        </workflow>
      XML
    end
    it { is_expected.to eq 'druid:mw971zk1113' }
  end

  describe '#workflow_name' do
    subject { instance.workflow_name }

    let(:xml) do
      <<~XML
        <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
        </workflow>
      XML
    end
    it { is_expected.to eq 'assemblyWF' }
  end

  describe '#repository' do
    subject { instance.repository }

    let(:xml) do
      <<~XML
        <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
        </workflow>
      XML
    end
    it { is_expected.to eq 'dor' }
  end

  describe '#active?' do
    subject { instance.active_for?(version: 2) }

    context 'when the workflow has not been instantiated for the given version' do
      let(:xml) do
        <<~XML
          <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
            <process version="1" laneId="default" elapsed="0.0" attempts="1" datetime="2013-02-18T14:40:25-0800" status="completed" name="start-assembly"/>
            <process version="1" laneId="default" elapsed="0.509" attempts="1" datetime="2013-02-18T14:42:24-0800" status="completed" name="jp2-create"/>
          </workflow>
        XML
      end
      it { is_expected.to be false }
    end

    context 'when the workflow has been instantiated for the given version' do
      let(:xml) do
        <<~XML
          <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
            <process version="1" laneId="default" elapsed="0.0" attempts="1" datetime="2013-02-18T14:40:25-0800" status="completed" name="start-assembly"/>
            <process version="1" laneId="default" elapsed="0.509" attempts="1" datetime="2013-02-18T14:42:24-0800" status="completed" name="jp2-create"/>
            <process version="2" laneId="default" elapsed="0.509" attempts="1" datetime="2013-02-18T14:42:24-0800" status="waiting" name="jp2-create"/>
          </workflow>
        XML
      end
      it { is_expected.to be true }
    end
  end

  describe '#empty?' do
    subject { instance.empty? }

    context 'when there is xml' do
      let(:xml) do
        '<?xml version="1.0" encoding="UTF-8"?>
          <workflow repository="dor" objectId="druid:oo201oo0001" id="accessionWF">
            <process version="2" lifecycle="submitted" elapsed="0.0" archived="true" attempts="1"
              datetime="2012-11-06T16:18:24-0800" status="completed" name="start-accession"/>
            <process version="2" elapsed="0.0" archived="true" attempts="1"
              datetime="2012-11-06T16:18:58-0800" status="completed" name="technical-metadata"/>
            <process version="2" elapsed="0.0" archived="true" attempts="1"
              datetime="2012-11-06T16:19:02-0800" status="completed" name="provenance-metadata"/>
            <process version="2" elapsed="0.0" archived="true" attempts="1"
              datetime="2012-11-06T16:19:05-0800" status="completed" name="remediate-object"/>
            <process version="2" elapsed="0.0" archived="true" attempts="1"
              datetime="2012-11-06T16:19:06-0800" status="completed" name="shelve"/>
            <process version="2" lifecycle="published" elapsed="0.0" archived="true" attempts="1"
              datetime="2012-11-06T16:19:07-0800" status="completed" name="publish"/>
            <process version="2" elapsed="0.0" archived="true" attempts="1"
              datetime="2012-11-06T16:19:09-0800" status="completed" name="sdr-ingest-transfer"/>
            <process version="2" lifecycle="accessioned" elapsed="0.0" archived="true" attempts="1"
              datetime="2012-11-06T16:19:10-0800" status="completed" name="cleanup"/>
            <process version="2" elapsed="0.0" archived="true" attempts="1"
              datetime="2012-11-06T16:19:13-0800" status="completed" name="rights-metadata"/>
            <process version="2" lifecycle="described" elapsed="0.0" archived="true" attempts="1"
              datetime="2012-11-06T16:19:15-0800" status="completed" name="descriptive-metadata"/>
            <process version="2" elapsed="0.0" archived="true" attempts="2"
              datetime="2012-11-06T16:19:16-0800" status="completed" name="content-metadata"/>
          </workflow>'
      end

      it { is_expected.to be false }
    end

    context 'when the xml is empty' do
      let(:xml) { '' }

      it { is_expected.to be true }
    end
  end

  describe '#process_for_recent_version' do
    subject(:process) { instance.process_for_recent_version(name: 'jp2-create') }

    context 'when the workflow has not been instantiated for the given version' do
      let(:xml) do
        <<~XML
          <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
            <process version="1" laneId="default" elapsed="0.0" attempts="1" datetime="2013-02-18T14:40:25-0800" status="completed" name="start-assembly"/>
            <process version="1" laneId="default" elapsed="0.509" attempts="1" datetime="2013-02-18T14:42:24-0800" status="completed" name="jp2-create"/>
          </workflow>
        XML
      end

      it 'returns a process' do
        expect(process).to be_kind_of Dor::Workflow::Response::Process
        expect(process.status).to eq 'completed'
        expect(process.name).to eq 'jp2-create'
      end
    end

    context 'when the workflow has been instantiated for the given version' do
      let(:xml) do
        <<~XML
          <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
            <process version="1" laneId="default" elapsed="0.0" attempts="1" datetime="2013-02-18T14:40:25-0800" status="completed" name="start-assembly"/>
            <process version="1" laneId="default" elapsed="0.509" attempts="1" datetime="2013-02-18T14:42:24-0800" status="completed" name="jp2-create"/>
            <process version="2" laneId="default" elapsed="0.509" attempts="1" datetime="2013-02-18T14:42:24-0800" status="error" name="jp2-create" errorMessage="it just broke"/>
          </workflow>
        XML
      end

      it 'returns a process' do
        expect(process).to be_kind_of Dor::Workflow::Response::Process
        expect(process.status).to eq 'error'
        expect(process.error_message).to eq 'it just broke'
        expect(process.name).to eq 'jp2-create'
      end
    end
  end
end
