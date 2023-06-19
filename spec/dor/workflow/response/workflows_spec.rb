# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Response::Workflows do
  subject(:instance) { described_class.new(xml: xml) }

  describe '#pid' do
    subject { instance.pid }

    let(:xml) do
      <<~XML
        <workflows objectId="druid:mw971zk1113">
        </workflows>
      XML
    end

    it { is_expected.to eq 'druid:mw971zk1113' }
  end

  describe '#workflows' do
    subject(:workflows) { instance.workflows }

    let(:xml) do
      <<~XML
        <workflows objectId="druid:mw971zk1113">
          <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
          </workflow>
          <workflow repository="dor" objectId="druid:mw971zk1113" id="sdrPreservationWF">
          </workflow>
        </workflows>
      XML
    end

    it 'has children' do
      expect(workflows).to all(be_kind_of Dor::Workflow::Response::Workflow)
      expect(workflows.map(&:workflow_name)).to eq %w[assemblyWF sdrPreservationWF]
    end
  end

  describe '#errors_for' do
    subject { instance.errors_for(version: 2) }

    let(:xml) do
      <<~XML
        <workflows objectId="druid:mw971zk1113">
          <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
            <process version="1" status="error" errorMessage="err1" />
            <process version="2" status="error" errorMessage="err2" />
            <process version="2" status="complete" errorMessage="err3" />
          </workflow>
          <workflow repository="dor" objectId="druid:mw971zk1113" id="sdrPreservationWF">
            <process version="1" status="error" errorMessage="err4" />
            <process version="2" status="error" errorMessage="err5" />
            <process version="2" status="complete" errorMessage="err6" />
          </workflow>
        </workflows>
      XML
    end

    it { is_expected.to eq %w[err2 err5] }
  end
end
