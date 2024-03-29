# frozen_string_literal: true

require 'spec_helper'

# This test can take up to 15s to run because it does retries with exponential backoff
RSpec.describe Dor::Workflow::Client::ConnectionFactory do
  let(:mock_logger) { double('Logger', info: true, debug: true, warn: true) }
  let(:client) { Dor::Workflow::Client.new url: 'http://example.com', logger: mock_logger }

  let(:druid) { 'druid:123' }
  let(:request_url) { "http://example.com/objects/#{druid}/workflows/httpException?lane-id=default&version=1" }

  before do
    stub_request(:post, request_url)
      .to_return(status: 500, body: 'Internal error', headers: {})
    allow(mock_logger).to receive(:warn)
  end

  describe '#create_workflow_by_name' do
    subject(:request) { client.create_workflow_by_name(druid, 'httpException', version: '1') }

    it 'logs an error and retry upon a targeted Faraday exception' do
      expect { request }.to raise_error Dor::WorkflowException
      expect(mock_logger).to have_received(:warn)
        .with("retrying connection (1) to #{request_url}: (Faraday::RetriableResponse)  500")
      expect(mock_logger).to have_received(:warn)
        .with("retrying connection (2) to #{request_url}: (Faraday::RetriableResponse)  500")
    end
  end
end
