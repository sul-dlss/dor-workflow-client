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
    subject { instance.workflows }

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
      expect(subject).to all(be_kind_of Dor::Workflow::Response::Workflow)
      expect(subject.map(&:workflow_name)).to eq %w[assemblyWF sdrPreservationWF]
    end
  end
end
