# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Client::WorkflowRoutes do
  let(:mock_requestor) { instance_double(Dor::Workflow::Client::Requestor) }

  let(:routes) { described_class.new(requestor: mock_requestor) }

  let(:wf_xml) do
    <<-EOXML
    <workflow id="etdSubmitWF">
         <process name="register-object" status="completed" attempts="1" />
         <process name="submit" status="waiting" />
         <process name="reader-approval" status="waiting" />
         <process name="registrar-approval" status="waiting" />
         <process name="start-accession" status="waiting" />
    </workflow>
    EOXML
  end

  describe '#add_lane_id_to_workflow_xml' do
    it 'adds laneId attributes to all process elements' do
      expected = <<-XML
        <workflow id="etdSubmitWF">
          <process name="register-object" status="completed" attempts="1" laneId="lane1"/>
          <process name="submit" status="waiting" laneId="lane1"/>
          <process name="reader-approval" status="waiting" laneId="lane1"/>
          <process name="registrar-approval" status="waiting" laneId="lane1"/>
          <process name="start-accession" status="waiting" laneId="lane1"/>
        </workflow>
      XML
      expect(routes.send(:add_lane_id_to_workflow_xml, 'lane1', wf_xml)).to be_equivalent_to(expected)
    end
  end

  describe '.workflow' do
    let(:xml) do
      <<~XML
        <workflow repository="dor" objectId="druid:mw971zk1113" id="accessionWF">
          <process laneId="default" lifecycle="submitted" elapsed="0.0" attempts="1" datetime="2013-02-18T15:08:10-0800" status="completed" name="start-accession"/>
        </workflow>
      XML
    end
    before do
      allow(routes).to receive(:workflow_xml) { xml }
    end

    it 'it returns a workflow' do
      expect(routes.workflow(pid: 'druid:mw971zk1113', workflow_name: 'accessionWF')).to be_kind_of Dor::Workflow::Response::Workflow
    end
  end
end
