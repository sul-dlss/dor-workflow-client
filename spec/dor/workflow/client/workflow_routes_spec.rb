# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Client::WorkflowRoutes do
  let(:mock_requestor) { instance_double(Dor::Workflow::Client::Requestor) }

  let(:routes) { described_class.new(requestor: mock_requestor) }

  describe '#fetch_workflow' do
    subject(:fetch_workflow) { routes.send(:fetch_workflow, druid: 'druid:mw971zk1113', workflow: workflow) }

    context 'when a workflow name is provided' do
      let(:workflow) { 'etdSubmitWF' }
      let(:mock_requestor) { instance_double(Dor::Workflow::Client::Requestor, request: xml) }
      let(:xml) { '<workflow id="etdSubmitWF"><process name="registrar-approval" status="completed" /></workflow>' }

      it 'returns the xml for a given repository, druid, and workflow' do
        expect(fetch_workflow).to eq(xml)
        expect(mock_requestor).to have_received(:request)
          .with('objects/druid:mw971zk1113/workflows/etdSubmitWF')
      end
    end

    context 'when no workflow name is provided' do
      let(:workflow) { nil }

      it 'raises an error' do
        expect { fetch_workflow }.to raise_error ArgumentError
      end
    end
  end

  describe '#workflow' do
    let(:xml) do
      <<~XML
        <workflow repository="dor" objectId="druid:mw971zk1113" id="accessionWF">
          <process laneId="default" lifecycle="submitted" elapsed="0.0" attempts="1" datetime="2013-02-18T15:08:10-0800" status="completed" name="start-accession"/>
        </workflow>
      XML
    end

    before do
      allow(routes).to receive(:fetch_workflow) { xml }
    end

    it 'returns a workflow' do
      expect(routes.workflow(pid: 'druid:mw971zk1113', workflow_name: 'accessionWF')).to be_kind_of Dor::Workflow::Response::Workflow
    end
  end

  describe '#process' do
    let(:xml) do
      <<~XML
        <workflow repository="dor" objectId="druid:mw971zk1113" id="accessionWF">
          <process laneId="default" lifecycle="submitted" elapsed="0.0" attempts="1" datetime="2013-02-18T15:08:10-0800" status="completed" name="start-accession"/>
        </workflow>
      XML
    end

    before do
      allow(routes).to receive(:fetch_workflow) { xml }
    end

    it 'returns a process' do
      expect(routes.process(pid: 'druid:mw971zk1113', workflow_name: 'accessionWF', process: 'start-accession')).to be_kind_of Dor::Workflow::Response::Process
    end
  end

  describe '#update_status' do
    let(:mock_requestor) { instance_double(Dor::Workflow::Client::Requestor, request: '{"next_steps":["submit-marc"]}') }
    let(:druid) { 'druid:mw971zk1113' }

    context 'when the request is successful' do
      it 'updates workflow status and return true if successful' do
        expect(routes.update_status(druid: druid, workflow: 'etdSubmitWF', process: 'registrar-approval', status: 'completed', note: 'annotation')).to be_kind_of Dor::Workflow::Response::Update
        expect(mock_requestor).to have_received(:request)
          .with('objects/druid:mw971zk1113/workflows/etdSubmitWF/registrar-approval',
                'put',
                "<?xml version=\"1.0\"?>\n<process name=\"registrar-approval\" status=\"completed\" elapsed=\"0\" note=\"annotation\"/>\n",
                content_type: 'application/xml')
      end
    end

    context 'when the PUT to the DOR workflow service throws an exception' do
      before do
        allow(mock_requestor).to receive(:request).and_raise(Dor::WorkflowException, 'status 400')
      end

      it 'raises an exception' do
        expect { routes.update_status(druid: druid, workflow: 'errorWF', process: 'registrar-approval', status: 'completed') }.to raise_error(Dor::WorkflowException, /status 400/)
      end
    end

    context 'when current-status is passed as a parameter' do
      it 'performs a conditional update' do
        expect(routes.update_status(druid: druid, workflow: 'etdSubmitWF', process: 'registrar-approval', status: 'completed', note: 'annotation', current_status: 'queued')).to be_kind_of Dor::Workflow::Response::Update
        expect(mock_requestor).to have_received(:request)
          .with('objects/druid:mw971zk1113/workflows/etdSubmitWF/registrar-approval?current-status=queued',
                'put',
                "<?xml version=\"1.0\"?>\n<process name=\"registrar-approval\" status=\"completed\" elapsed=\"0\" note=\"annotation\"/>\n",
                content_type: 'application/xml')
      end
    end

    context 'when an invalid status is provided' do
      it 'throws an exception' do
        expect { routes.update_status(druid: druid, workflow: 'accessionWF', process: 'publish', status: 'NOT_VALID_STATUS') }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#update_error_status' do
    let(:mock_requestor) { instance_double(Dor::Workflow::Client::Requestor, request: '{"next_steps":["submit-marc"]}') }
    let(:druid) { 'druid:mw971zk1113' }

    context 'when the request is successful' do
      it 'updates workflow status and return true if successful' do
        expect(routes.update_error_status(druid: druid, workflow: 'etdSubmitWF', process: 'registrar-approval', error_msg: 'broken')).to be_kind_of Dor::Workflow::Response::Update
        expect(mock_requestor).to have_received(:request)
          .with('objects/druid:mw971zk1113/workflows/etdSubmitWF/registrar-approval',
                'put',
                "<?xml version=\"1.0\"?>\n<process name=\"registrar-approval\" status=\"error\" errorMessage=\"broken\"/>\n",
                content_type: 'application/xml')
      end
    end

    context 'when the PUT to the DOR workflow service throws an exception' do
      before do
        allow(mock_requestor).to receive(:request).and_raise(Dor::WorkflowException, 'status 400')
      end

      it 'raises an exception' do
        expect { routes.update_error_status(druid: druid, workflow: 'errorWF', process: 'registrar-approval', error_msg: 'broken') }.to raise_error(Dor::WorkflowException, /status 400/)
      end
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

    it 'returns the workflows' do
      expect(routes.all_workflows(pid: 'druid:mw971zk1113')).to be_kind_of Dor::Workflow::Response::Workflows
    end
  end

  describe '#create_workflow_by_name' do
    it 'need to write these specs', skip: 'need to write specs' do
      # something
    end
  end
end
