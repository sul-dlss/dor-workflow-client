# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Response::Process do
  subject(:instance) { parent.process_for_recent_version(name: 'start-assembly') }

  let(:parent) { Dor::Workflow::Response::Workflow.new(xml: xml) }

  describe '#pid' do
    subject { instance.pid }

    let(:xml) do
      <<~XML
        <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
          <process name="start-assembly">
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
          <process name="start-assembly">
        </workflow>
      XML
    end

    it { is_expected.to eq 'assemblyWF' }
  end

  describe '#name' do
    subject { instance.name }

    let(:xml) do
      <<~XML
        <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
          <process name="start-assembly">
        </workflow>
      XML
    end

    it { is_expected.to eq 'start-assembly' }
  end

  describe '#lane_id' do
    subject { instance.lane_id }

    let(:xml) do
      <<~XML
        <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
          <process name="start-assembly" laneId="default">
        </workflow>
      XML
    end

    it { is_expected.to eq 'default' }
  end

  describe '#context' do
    subject { instance.context }

    context 'when context exists' do
      let(:xml) do
        <<~XML
          <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
            <process name="start-assembly" laneId="default" context="{&quot;requireOCR&quot;:true}">
          </workflow>
        XML
      end

      it { is_expected.to eq({ 'requireOCR' => true }) }
    end

    context 'when no context exists' do
      let(:xml) do
        <<~XML
          <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
            <process name="start-assembly" laneId="default" context="">
          </workflow>
        XML
      end

      it { is_expected.to eq({}) }
    end
  end
end
