# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Client::WorkflowTemplate do
  let(:mock_requestor) { instance_double(Dor::Workflow::Client::Requestor, request: data) }

  let(:routes) { described_class.new(requestor: mock_requestor) }

  describe '#retrieve' do
    subject(:workflow_template) { routes.retrieve('accessionWF') }
    let(:data) { '{"processes":[{"name":"start-assembly"},{"name":"content-metadata-create"}]}' }

    it 'returns a workflow template' do
      expect(workflow_template['processes']).to eq [{ 'name' => 'start-assembly' },
                                                    { 'name' => 'content-metadata-create' }]
      expect(mock_requestor).to have_received(:request).with('workflow_templates/accessionWF')
    end
  end

  describe '#all' do
    subject(:workflow_templates) { routes.all }
    let(:data) { '["assemblyWF","registrationWF"]' }

    it 'returns a list of templates' do
      expect(workflow_templates).to eq %w[assemblyWF registrationWF]
      expect(mock_requestor).to have_received(:request).with('workflow_templates')
    end
  end
end
