require 'spec_helper'

describe Dor::WorkflowService do
  before :each do
    @logger1 = double('Logger')
  end
  describe '#configure' do
    it 'pulls default_logger if not specified' do
      allow_any_instance_of(Dor::WorkflowService).to receive(:default_logger).and_return(@logger1)
      wfs = Dor::WorkflowService.new('https://dortest.stanford.edu/workflow')
      expect(wfs.logger).to eq @logger1
    end
    it 'accepts :logger if specified' do
      wfs = Dor::WorkflowService.new('https://dortest.stanford.edu/workflow', :logger => @logger1)
      expect(wfs.logger).to eq @logger1
    end
  end
end
