require 'spec_helper'

describe Dor::WorkflowService do
  before :each do
    @url = 'http://example.com/foobar'
  end
  describe '#new' do
    describe ':cache_enabled' do
      context 'when :cache not supplied' do
        it 'defaults to false, but can be set' do
          wfs = Dor::WorkflowService.new(@url)
          expect(wfs.cache_enabled).to be_falsey
          expect(wfs.cache).to be_a(ActiveSupport::Cache::MemoryStore) # cache still initialized, possible TODO: don't initialize until enabled
          wfs.cache_enabled = true
          expect(wfs.cache_enabled).to be_truthy
          expect(wfs.cache).to be_a(ActiveSupport::Cache::MemoryStore)
        end
        it 'initializes cache if :cache_enabled' do
          wfs = Dor::WorkflowService.new(@url, :cache_enabled => true)
          expect(wfs.cache_enabled).to be_truthy
          expect(wfs.cache).to be_a(ActiveSupport::Cache::MemoryStore)
        end
      end
      context 'when :cache supplied' do
        before :each do
          @memstore = ActiveSupport::Cache::MemoryStore.new
        end
        it 'defaults to true' do
          wfs = Dor::WorkflowService.new(@url, :cache => @memstore)
          expect(wfs.cache_enabled).to be_truthy
          expect(wfs.cache).to eq(@memstore)
        end
        it 'still respects cache_enabled being false' do
          wfs = Dor::WorkflowService.new(@url, :cache => @memstore, :cache_enabled => false)
          expect(wfs.cache_enabled).to be_falsey
          expect(wfs.cache).to eq(@memstore)
        end
      end
    end
  end
end
