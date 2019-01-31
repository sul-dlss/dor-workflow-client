# frozen_string_literal: true

require 'spec_helper'

describe Dor::WorkflowService do
  before :each do
    @logger1 = double('Logger')
    allow(Dor::WorkflowService).to receive(:default_logger).and_return(@logger1)
  end
  describe '#configure' do
    it 'pulls default_logger if not specified' do
      expect(Dor::WorkflowService).to receive(:default_logger).and_return(@logger1)
      Dor::WorkflowService.configure('https://dortest.stanford.edu/workflow')
    end
    it 'accepts :logger if specified' do
      expect(Dor::WorkflowService).not_to receive(:default_logger)
      Dor::WorkflowService.configure('https://dortest.stanford.edu/workflow', logger: @logger1)
    end
  end
end
