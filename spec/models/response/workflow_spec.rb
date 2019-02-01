# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Response::Workflow do
  subject(:instance) { described_class.new(xml: xml) }

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
end
