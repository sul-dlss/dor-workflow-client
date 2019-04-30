# frozen_string_literal: true

require 'spec_helper'

# This test can take up to 15s to run because it does retries with exponential backoff
RSpec.describe Dor::Workflow::Client::ConnectionFactory do
  let(:mock_logger) { double('Logger', info: true, debug: true, warn: true) }

  let(:druid) { 'druid:123' }
  before do
    stub_request(:post, "http://example.com/objects/#{druid}/workflows/httpException?create-ds=true&lane-id=default")
      .to_return(status: 500, body: 'Internal error', headers: {})
  end

  let(:client) { Dor::Workflow::Client.new url: 'http://example.com', logger: mock_logger }

  describe '#create_workflow_by_name' do
    it 'logs an error and retry upon a targeted Faraday exception' do
      expect(mock_logger).to receive(:warn).with('retrying connection (1 remaining) to http://example.com/objects/druid:123/workflows/httpException?create-ds=true&lane-id=default: (Faraday::RetriableResponse)  500')
      expect(mock_logger).to receive(:warn).with('retrying connection (0 remaining) to http://example.com/objects/druid:123/workflows/httpException?create-ds=true&lane-id=default: (Faraday::RetriableResponse)  500')
      expect { client.create_workflow_by_name(druid, 'httpException') }.to raise_error Dor::WorkflowException
    end
  end
end
