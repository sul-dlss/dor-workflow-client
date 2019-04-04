# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Client::Requestor do
  let(:mock_http_connection) do
    Faraday.new(url: 'http://example.com/') do |builder|
      builder.use Faraday::Response::RaiseError
      builder.options.params_encoder = Faraday::FlatParamsEncoder

      builder.adapter :test, stubs
    end
  end

  let(:mock_logger) { double('Logger', info: true, debug: true, warn: true) }
  let(:requestor) { described_class.new(connection: mock_http_connection, logger: mock_logger) }

  describe '.send_workflow_resource_request' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('x?complete=a&complete=b') do |_env|
          [200, {}, 'ab']
        end
      end
    end

    it 'uses the flat params encoder' do
      response = requestor.send(:send_workflow_resource_request, 'x?complete=a&complete=b')

      expect(response.body).to eq 'ab'
      expect(response.env.url.query).to eq 'complete=a&complete=b'
    end
  end
end
