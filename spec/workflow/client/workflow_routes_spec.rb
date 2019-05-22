# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Client::WorkflowRoutes do
  let(:mock_requestor) { instance_double(Dor::Workflow::Client::Requestor) }

  let(:routes) { described_class.new(requestor: mock_requestor) }

  describe '#workflow' do
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

    it 'returns a workflow' do
      expect(routes.workflow(pid: 'druid:mw971zk1113', workflow_name: 'accessionWF')).to be_kind_of Dor::Workflow::Response::Workflow
    end
  end

  describe '#delete_all_workflows' do
    subject(:delete_all_workflows) do
      routes.delete_all_workflows(pid: 'druid:mw971zk1113')
    end
    let(:mock_requestor) { instance_double(Dor::Workflow::Client::Requestor, request: nil) }

    it 'sends a delete request' do
      delete_all_workflows
      expect(mock_requestor).to have_received(:request)
        .with('objects/druid:mw971zk1113/workflows', 'delete')
    end
  end

  describe '#all_workflows' do
    let(:xml) do
      <<~XML
        <workflows objectId="druid:mw971zk1113">
          <workflow repository="dor" objectId="druid:mw971zk1113" id="accessionWF">
            <process laneId="default" lifecycle="submitted" elapsed="0.0" attempts="1" datetime="2013-02-18T15:08:10-0800" status="completed" name="start-accession"/>
          </workflow>
        </workflows>
      XML
    end

    before do
      allow(routes).to receive(:all_workflows_xml) { xml }
    end

    it 'it returns the workflows' do
      expect(routes.all_workflows(pid: 'druid:mw971zk1113')).to be_kind_of Dor::Workflow::Response::Workflows
    end
  end

  describe '#create_workflow_by_name' do
  end
end
