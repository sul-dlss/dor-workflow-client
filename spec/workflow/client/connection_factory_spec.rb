# frozen_string_literal: true

require 'spec_helper'

# This test can take up to 15s to run because it does retries with exponential backoff
RSpec.describe Dor::Workflow::Client::ConnectionFactory do
  let(:mock_logger) { double('Logger', info: true, debug: true, warn: true) }

  let(:repo) { 'dor' }
  let(:druid) { 'druid:123' }
  before do
    stub_request(:put, "http://example.com/#{repo}/objects/#{druid}/workflows/httpException?create-ds=true")
      .to_return(status: 500, body: 'Internal error', headers: {})
  end

  let(:client) { Dor::Workflow::Client.new url: 'http://example.com', logger: mock_logger }

  describe '#create_workflow' do
    it 'logs an error and retry upon a targeted Faraday exception' do
      expect(mock_logger).to receive(:warn).with('retrying connection (1 remaining) to http://example.com/dor/objects/druid:123/workflows/httpException?create-ds=true: (Faraday::RetriableResponse)  500')
      expect(mock_logger).to receive(:warn).with('retrying connection (0 remaining) to http://example.com/dor/objects/druid:123/workflows/httpException?create-ds=true: (Faraday::RetriableResponse)  500')
      expect { client.create_workflow(repo, druid, 'httpException', '<xml>') }.to raise_error Dor::WorkflowException
    end
  end
end
