# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Client::WorkflowTemplate do
  let(:data) { '{"processes":[{"name":"start-assembly"},{"name":"content-metadata-create"}]}' }
  let(:mock_requestor) { instance_double(Dor::Workflow::Client::Requestor, request: data) }

  let(:routes) { described_class.new(requestor: mock_requestor) }

  describe '#retrieve' do
    subject(:workflow_template) { routes.retrieve('accessionWF') }

    it 'returns a workflow' do
      expect(workflow_template['processes']).to eq [{ 'name' => 'start-assembly' },
                                                    { 'name' => 'content-metadata-create' }]
      expect(mock_requestor).to have_received(:request).with('workflow_templates/accessionWF')
    end
  end
end
