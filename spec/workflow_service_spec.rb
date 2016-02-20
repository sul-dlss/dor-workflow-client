require 'spec_helper'

describe Dor::WorkflowService do
  let(:wf_xml) { <<-EOXML
    <workflow id="etdSubmitWF">
         <process name="register-object" status="completed" attempts="1" />
         <process name="submit" status="waiting" />
         <process name="reader-approval" status="waiting" />
         <process name="registrar-approval" status="waiting" />
         <process name="start-accession" status="waiting" />
    </workflow>
    EOXML
  }

  let(:wf_xml_label) { <<-EOXML
<?xml version="1.0"?>
<workflow id="etdSubmitWF">
         <process name="register-object" status="completed" attempts="1" laneId="default"/>
         <process name="submit" status="waiting" laneId="default"/>
         <process name="reader-approval" status="waiting" laneId="default"/>
         <process name="registrar-approval" status="waiting" laneId="default"/>
         <process name="start-accession" status="waiting" laneId="default"/>
    </workflow>
    EOXML
  }

  let(:stubs) do
    Faraday::Adapter::Test::Stubs.new
  end

  let(:mock_http_connection) do
    Faraday.new(url: 'http://example.com/') do |builder|
      builder.use Faraday::Response::RaiseError

      builder.adapter :test, stubs
    end
  end

  before(:each) do
    @repo  = 'dor'
    @druid = 'druid:123'
  end

  let(:mock_logger) do
    mock_logger = double('Logger')

    allow(mock_logger).to receive(:info)  # silence log output
    allow(mock_logger).to receive(:debug) # silence log output
    allow(mock_logger).to receive(:warn) # silence log output

    mock_logger
  end

  subject do
    described_class.new(mock_http_connection, logger: mock_logger)
  end

  describe '#configure' do
    subject { described_class.new 'http://externalhost/', timeout: 99, logger: mock_logger }

    it 'should handle a string and timeout' do
      expect(subject.workflow_resource).to be_a(Faraday::Connection)
      expect(subject.workflow_resource.options.timeout).to eq(99)
      expect(subject.workflow_resource.options.open_timeout).to eq(99)
    end
  end

  describe '#create_workflow' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.put("#{@repo}/objects/#{@druid}/workflows/etdSubmitWF") { |env| [201, {}, ''] }
        stub.put("#{@repo}/objects/#{@druid}/workflows/noCreateDsWF?create-ds=false") { |env| [201, {}, ''] }
        stub.put("#{@repo}/objects/#{@druid}/workflows/httpException") { |env| [418, {}, "I'm A Teapot"] }
        stub.put("#{@repo}/objects/#{@druid}/workflows/raiseException") { |env| raise 'broken' }
      end
    end

    it 'should pass workflow xml to the DOR workflow service and return the URL to the workflow' do
      subject.create_workflow(@repo, @druid, 'etdSubmitWF', wf_xml)
    end

    it 'should log an error and retry upon a targetted Faraday exception' do
      expect(mock_logger).to receive(:warn).with(/\[Attempt 1\] Faraday::ClientError: the server responded with status 418/)
      expect { subject.create_workflow(@repo, @druid, 'httpException', wf_xml) }.to raise_error Dor::WorkflowException
    end

    it 'should raise on an unexpected Exception' do
      expect{ subject.create_workflow(@repo, @druid, 'raiseException', wf_xml) }.to raise_error(Exception, 'broken')
    end

    it 'sets the create-ds param to the value of the passed in options hash' do
      subject.create_workflow(@repo, @druid, 'noCreateDsWF', wf_xml, :create_ds => false)
    end
  end

  describe '#add_lane_id_to_workflow_xml' do
    it 'adds laneId attributes to all process elements' do
      expected = <<-XML
        <workflow id="etdSubmitWF">
          <process name="register-object" status="completed" attempts="1" laneId="lane1"/>
          <process name="submit" status="waiting" laneId="lane1"/>
          <process name="reader-approval" status="waiting" laneId="lane1"/>
          <process name="registrar-approval" status="waiting" laneId="lane1"/>
          <process name="start-accession" status="waiting" laneId="lane1"/>
        </workflow>
      XML
      expect(subject.send(:add_lane_id_to_workflow_xml, 'lane1', wf_xml)).to be_equivalent_to(expected)
    end
  end

  describe '#update_workflow_status' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.put("#{@repo}/objects/#{@druid}/workflows/etdSubmitWF/reader-approval?current-status=queued") do |env|
          [201, {}, '']
        end

        stub.put("#{@repo}/objects/#{@druid}/workflows/etdSubmitWF/reader-approval") do |env|
          expect(env.body).to eq "<?xml version=\"1.0\"?>\n<process name=\"reader-approval\" status=\"completed\" elapsed=\"0\" note=\"annotation\" version=\"2\" laneId=\"lane2\"/>\n"
          [201, {}, '']
        end

        stub.put("#{@repo}/objects/#{@druid}/workflows/errorWF/reader-approval") do |env|
          [400, {}, '']
        end
      end
    end

    it 'should update workflow status and return true if successful' do
      expect(subject.update_workflow_status(@repo, @druid, 'etdSubmitWF', 'reader-approval', 'completed', :version => 2, :note => 'annotation', :lane_id => 'lane2')).to be true
    end

    it 'should return false if the PUT to the DOR workflow service throws an exception' do
      expect{ subject.update_workflow_status(@repo, @druid, 'errorWF', 'reader-approval', 'completed') }.to raise_error(Dor::WorkflowException, /status 400/)
    end

    it 'performs a conditional update when current-status is passed as a parameter' do
      expect(mock_http_connection).to receive(:put).with("#{@repo}/objects/#{@druid}/workflows/etdSubmitWF/reader-approval?current-status=queued").and_call_original

      expect(subject.update_workflow_status(@repo, @druid, 'etdSubmitWF', 'reader-approval', 'completed', :version => 2, :note => 'annotation', :lane_id => 'lane1', :current_status => 'queued')).to be true
    end

    it 'should throw exception if invalid status provided' do
      expect { subject.update_workflow_status(@repo, @druid, 'accessionWF', 'publish', 'NOT_VALID_STATUS') }.to raise_error(ArgumentError)
    end
  end

  describe '#update_workflow_error_status' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.put("#{@repo}/objects/#{@druid}/workflows/etdSubmitWF/reader-approval") do |env|
          expect(env.body).to match /status="error" errorMessage="Some exception" errorText="The optional stacktrace"/
          [201, {}, '']
        end

        stub.put("#{@repo}/objects/#{@druid}/workflows/errorWF/reader-approval") do |env|
          [400, {}, '']
        end
      end
    end

    it 'should update workflow status to error and return true if successful' do
      subject.update_workflow_error_status(@repo, @druid, 'etdSubmitWF', 'reader-approval', 'Some exception', :error_text =>'The optional stacktrace')
    end
    it 'should return false if the PUT to the DOR workflow service throws an exception' do
      expect{ subject.update_workflow_status(@repo, @druid, 'errorWF', 'reader-approval', 'completed') }.to raise_error(Dor::WorkflowException, /status 400/)
    end
  end

  describe '#get_workflow_status' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("#{@repo}/objects/#{@druid}/workflows/etdSubmitWF") do |env|
          [200, {}, '<process name="registrar-approval" status="completed" />']
        end

        stub.get("#{@repo}/objects/#{@druid}/workflows/missingWF") do |env|
          [404, {}, '']
        end

        stub.get("#{@repo}/objects/#{@druid}/workflows/errorWF") do |env|
          [200, {}, 'something not xml']
        end

        stub.get("#{@repo}/objects/#{@druid}/workflows/accessionWF") do |env|
          [200, {}, '<process name="registrar-approval" status="completed" />']
        end
      end
    end

    it 'parses workflow xml and returns status as a string' do
      expect(subject.get_workflow_status('dor', 'druid:123', 'etdSubmitWF', 'registrar-approval')).to eq('completed')
    end
    it 'should throw an exception if it fails for any reason' do
      expect{ subject.get_workflow_status('dor', 'druid:123', 'missingWF', 'registrar-approval') }.to raise_error Dor::WorkflowException
    end
    it 'should throw an exception if it cannot parse the response' do
      expect{ subject.get_workflow_status('dor', 'druid:123', 'errorWF', 'registrar-approval') }.to raise_error(Dor::WorkflowException, "Unable to parse response:\nsomething not xml")
    end
    it 'should return nil if the workflow/process combination doesnt exist' do
      expect(subject.get_workflow_status('dor', 'druid:123', 'accessionWF', 'publish')).to be_nil
    end
  end

  describe '#get_workflow_xml' do
    let(:xml) { '<workflow id="etdSubmitWF"><process name="registrar-approval" status="completed" /></workflow>' }
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("dor/objects/druid:123/workflows/etdSubmitWF") do |env|
          [200, {}, xml]
        end
      end
    end

    it 'returns the xml for a given repository, druid, and workflow' do
      expect(subject.get_workflow_xml('dor', 'druid:123', 'etdSubmitWF')).to eq(xml)
    end
  end

  describe '#get_workflows' do
    let(:xml) { '<workflow id="accessionWF"><process name="publish" status="completed" /></workflow>' }
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("dor/objects/#{@druid}/workflows/") do |env|
          [200, {}, xml]
        end
      end
    end

    it 'returns the workflows associated with druid' do
      expect(subject.get_workflows(@druid)).to eq(['accessionWF'])
    end
  end

  describe '#get_lifecycle' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('dor/objects/druid:123/lifecycle') do |env|
          [200, {}, <<-EOXML]
            <lifecycle objectId="druid:ct011cv6501">
                <milestone date="2010-04-27T11:34:17-0700">registered</milestone>
                <milestone date="2010-04-29T10:12:51-0700">inprocess</milestone>
                <milestone date="2010-06-15T16:08:58-0700">released</milestone>
            </lifecycle>
          EOXML
        end

        stub.get('dor/objects/druid:abc/lifecycle') do |env|
          [200, {}, <<-EOXML]
            <lifecycle />
          EOXML
        end
      end
    end

    it 'returns a Time object reprenting when the milestone was reached' do
      expect(subject.get_lifecycle('dor', 'druid:123', 'released').beginning_of_day).to eq(Time.parse('2010-06-15T16:08:58-0700').beginning_of_day)
    end

    it "returns nil if the milestone hasn't been reached yet" do
      expect(subject.get_lifecycle('dor', 'druid:abc', 'inprocess')).to be_nil
    end
  end

  describe '#get_active_lifecycle' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("dor/objects/#{@druid}/lifecycle") do |env|
          [200, {}, <<-EOXML]
            <lifecycle objectId="#{@druid}">
                <milestone date="2010-04-27T11:34:17-0700">registered</milestone>
                <milestone date="2010-04-29T10:12:51-0700">inprocess</milestone>
                <milestone date="2010-06-15T16:08:58-0700">released</milestone>
            </lifecycle>
          EOXML
        end

        stub.get("dor/objects/#{@druid}/lifecycle") do |env|
          [200, {}, <<-EOXML]
            <lifecycle />
          EOXML
        end
      end
    end

    it 'parses out the active lifecycle' do
      expect(subject.get_active_lifecycle('dor', @druid, 'released').beginning_of_day).to eq(Time.parse('2010-06-15T16:08:58-0700').beginning_of_day)
    end

    it 'handles missing lifecycle' do
      expect(subject.get_active_lifecycle('dor', @druid, 'NOT_FOUND')).to be_nil
    end
  end

  context '#get_objects_for_workstep' do
    before :all do
      @repository = 'dor'
      @workflow   = 'googleScannedBookWF'
      @completed  = 'google-download'
      @waiting    = 'process-content'
    end

    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("workflow_queue?waiting=#{@repository}:#{@workflow}:#{@waiting}&completed=#{@repository}:#{@workflow}:#{@completed}&lane-id=default") do |env|
          [200, {}, '<objects count="1"><object id="druid:ab123de4567"/><object id="druid:ab123de9012"/></objects>']
        end
      end
    end

    describe 'a query with one step completed and one waiting' do
      it 'creates the URI string with only the one completed step' do
        expect(subject.get_objects_for_workstep(@completed, @waiting, 'default', :default_repository => @repository, :default_workflow => @workflow)).to eq(['druid:ab123de4567', 'druid:ab123de9012'])
      end
    end

    describe 'a query with TWO steps completed and one waiting' do
      it 'creates the URI string with the two completed steps correctly' do
        second_completed = 'google-convert'
        xml = %{<objects count="1"><object id="druid:ab123de4567"/><object id="druid:ab123de9012"/></objects>}
        allow(mock_http_connection).to receive(:get).with("workflow_queue?waiting=#{@repository}:#{@workflow}:#{@waiting}&completed=#{@repository}:#{@workflow}:#{@completed}&completed=#{@repository}:#{@workflow}:#{second_completed}&lane-id=default").and_return(double Faraday::Response, :body => xml)
        expect(subject.get_objects_for_workstep([@completed, second_completed], @waiting, 'default', :default_repository => @repository, :default_workflow => @workflow)).to eq(['druid:ab123de4567', 'druid:ab123de9012'])
      end
    end

    context 'a query using qualified workflow names for completed and waiting' do
      before :each do
        @qualified_waiting   = "#{@repository}:#{@workflow}:#{@waiting}"
        @qualified_completed = "#{@repository}:#{@workflow}:#{@completed}"
      end

      RSpec.shared_examples 'lane-aware' do
        it 'creates the URI string with the two completed steps across repositories correctly' do
          qualified_completed2 = "sdr:sdrIngestWF:complete-deposit"
          qualified_completed3 = "sdr:sdrIngestWF:ingest-transfer"
          xml = %{<objects count="2"><object id="druid:ab123de4567"/><object id="druid:ab123de9012"/></objects>}
          allow(mock_http_connection).to receive(:get).with("workflow_queue?waiting=#{@qualified_waiting}&completed=#{@qualified_completed}&completed=#{qualified_completed2}&completed=#{qualified_completed3}&lane-id=#{laneid}").and_return(double Faraday::Response, :body => xml)
          args = [[@qualified_completed, qualified_completed2, qualified_completed3], @qualified_waiting]
          args << laneid if laneid != 'default'
          expect(subject.get_objects_for_workstep(*args)).to eq(['druid:ab123de4567', 'druid:ab123de9012'])
        end
      end

      describe 'default lane_id' do
        it_behaves_like 'lane-aware' do
          let(:laneid) { 'default' }
        end
      end
      describe 'explicit lane_id' do
        it_behaves_like 'lane-aware' do
          let(:laneid) { 'lane1' }
        end
      end

      context 'URI string creation' do
        before :each do
          @xml = %{<objects count="1"><object id="druid:ab123de4567"/></objects>}
        end
        it 'with only one completed step passed in as a String' do
          allow(mock_http_connection).to receive(:get).with("workflow_queue?waiting=#{@qualified_waiting}&completed=#{@qualified_completed}&lane-id=default").and_return(double Faraday::Response, :body => @xml)
          expect(subject.get_objects_for_workstep(@qualified_completed, @qualified_waiting)).to eq(['druid:ab123de4567'])
        end
        it 'without any completed steps, only waiting' do
          allow(mock_http_connection).to receive(:get).with("workflow_queue?waiting=#{@qualified_waiting}&lane-id=default").and_return(double Faraday::Response, :body => @xml)
          expect(subject.get_objects_for_workstep(nil, @qualified_waiting)).to eq(['druid:ab123de4567'])
        end
        it 'same but with lane_id' do
          allow(mock_http_connection).to receive(:get).with("workflow_queue?waiting=#{@qualified_waiting}&lane-id=lane1").and_return(double Faraday::Response, :body => @xml)
          expect(subject.get_objects_for_workstep(nil, @qualified_waiting, 'lane1')).to eq([ 'druid:ab123de4567' ])
        end
      end
    end
  end

  context 'get empty workflow queue' do
    before(:all) do
      @repository = 'dor'
      @workflow   = 'googleScannedBookWF'
      @completed  = 'google-download'
      @waiting    = 'process-content'
    end

    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("workflow_queue?waiting=#{@repository}:#{@workflow}:#{@waiting}&completed=#{@repository}:#{@workflow}:#{@completed}&lane-id=default") do |env|
          [200, {}, '<objects count="0"/>']
        end
      end
    end

    it 'returns an empty list if it encounters an empty workflow queue' do
      expect(subject.get_objects_for_workstep(@completed, @waiting, 'default', :default_repository => @repository, :default_workflow => @workflow)).to eq([])
    end
  end

  context 'get errored workflow steps' do
    before(:all) do
      @repository = 'dor'
      @workflow   = 'accessionWF'
      @step       = 'publish'
    end

    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/workflow_queue?error=#{@step}&repository=#{@repository}&workflow=#{@workflow}") do |env|
          [200, {}, <<-EOXML ]
            <objects count="1">
               <object id="druid:ab123cd4567" errorMessage="This is an error message"/>
             </objects>
            EOXML
        end
      end
    end

    it 'returns error messages for errored objects' do
      expect(subject.get_errored_objects_for_workstep(@workflow, @step, @repository)).to eq({'druid:ab123cd4567'=>'This is an error message'})
    end

    it 'counts how many steps are errored out' do
      expect(subject.count_errored_for_workstep(@workflow, @step, @repository)).to eq(1)
    end
  end

  describe '#count_queued_for_workstep' do
    before(:all) do
      @repository = 'dor'
      @workflow   = 'accessionWF'
      @step       = 'publish'
    end

    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/workflow_queue?queued=#{@step}&repository=#{@repository}&workflow=#{@workflow}") do |env|
          [200, {}, <<-EOXML ]
            <objects count="1">
               <object id="druid:ab123cd4567"/>
             </objects>
            EOXML
        end
      end
    end

    it 'counts how many steps are errored out' do
      expect(subject.count_queued_for_workstep(@workflow, @step, @repository)).to eq(1)
    end
  end

  describe '#count_archived_for_workflow' do
    before(:all) do
      @repository = 'dor'
      @workflow   = 'accessionWF'
    end

    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/workflow_archive?repository=#{@repository}&workflow=#{@workflow}&count-only=true") do |env|
          [200, {}, <<-EOXML ]
            <objects count="20" />
            EOXML
        end
      end
    end

    it 'counts how many workflows are archived' do
      expect(subject.count_archived_for_workflow(@workflow, @repository)).to eq(20)
    end
  end

  describe '#delete_workflow' do
    let(:url) { "#{@repo}/objects/#{@druid}/workflows/accessionWF" }

    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.delete(url) { |env| [202, {}, ''] }
      end
    end

    it 'sends a delete request to the workflow service' do
      expect(mock_http_connection).to receive(:delete).with(url).and_call_original
      subject.delete_workflow(@repo, @druid, 'accessionWF')
    end
  end
  describe 'get_milestones' do
    it 'should include the version in with the milestones' do
      xml = '<?xml version="1.0" encoding="UTF-8"?><lifecycle objectId="druid:gv054hp4128"><milestone date="2012-01-26T21:06:54-0800" version="2">published</milestone></lifecycle>'
      xml = Nokogiri::XML(xml)
      allow(subject).to receive(:query_lifecycle).and_return(xml)
      milestones = subject.get_milestones(@repo, @druid)
      expect(milestones.first[:milestone]).to eq('published')
      expect(milestones.first[:version]).to eq('2')
    end
  end

  describe '.get_active_workflows' do
    it 'it returns an array of active workflows only' do
      xml = <<-XML
      <workflows objectId="druid:mw971zk1113">
        <workflow repository="dor" objectId="druid:mw971zk1113" id="accessionWF">
          <process laneId="default" lifecycle="submitted" elapsed="0.0" attempts="1" datetime="2013-02-18T15:08:10-0800" status="completed" name="start-accession"/>
        </workflow>
        <workflow repository="dor" objectId="druid:mw971zk1113" id="assemblyWF">
          <process version="1" laneId="default" elapsed="0.0" archived="true" attempts="1" datetime="2013-02-18T14:40:25-0800" status="completed" name="start-assembly"/>
          <process version="1" laneId="default" elapsed="0.509" archived="true" attempts="1" datetime="2013-02-18T14:42:24-0800" status="completed" name="jp2-create"/>
        </workflow>
      </workflows>
      XML
      allow(subject).to receive(:get_workflow_xml) { xml }
      expect(subject.get_active_workflows('dor', 'druid:mw971zk1113')).to eq(['accessionWF'])
    end
  end

  describe '#close_version' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post('dor/objects/druid:123/versionClose?create-accession=false') do |env|
          [202, {}, '']
        end

        stub.post('dor/objects/druid:123/versionClose') do |env|
          [202, {}, '']
        end
      end
    end

    let(:url) { 'dor/objects/druid:123/versionClose' }
    it 'calls the versionClose endpoint with druid' do
      subject.close_version(@repo, @druid)
    end

    it 'optionally prevents creation of accessionWF' do
      expect(mock_http_connection).to receive(:post).with('dor/objects/druid:123/versionClose?create-accession=false').and_call_original
      subject.close_version(@repo, @druid, false)
    end
  end

  describe '.get_stale_queued_workflows' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('workflow_queue/all_queued?repository=dor&hours-ago=24&limit=100') do |env|
          [200, {}, <<-XML]
          <workflows>
              <workflow laneId="lane1" note="annotation" lifecycle="in-process" errorText="stacktrace" errorMessage="NullPointerException" elapsed="1.173" repository="dor" attempts="0" datetime="2008-11-15T13:30:00-0800" status="waiting" process="content-metadata" name="accessionWF" druid="dr:123"/>
              <workflow laneId="lane2" note="annotation" lifecycle="in-process" errorText="stacktrace" errorMessage="NullPointerException" elapsed="1.173" repository="dor" attempts="0" datetime="2008-11-15T13:30:00-0800" status="waiting" process="jp2-create" name="assemblyWF" druid="dr:456"/>
          </workflows>
          XML
        end
      end
    end

    it 'returns an Array of Hashes containing each workflow step' do
      ah = subject.get_stale_queued_workflows 'dor', :hours_ago => 24, :limit => 100
      expected = [
        { :workflow => 'accessionWF', :step => 'content-metadata', :druid => 'dr:123', :lane_id => 'lane1' },
        { :workflow => 'assemblyWF',  :step => 'jp2-create',       :druid => 'dr:456', :lane_id => 'lane2' }
      ]
      expect(ah).to eql(expected)
    end
  end

  describe '.count_stale_queued_workflows' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('workflow_queue/all_queued?repository=dor&hours-ago=48&count-only=true') do |env|
          [200, {}, '<objects count="10"/>']
        end
      end
    end

    it 'returns the number of queued workflow steps' do
      expect(subject.count_stale_queued_workflows('dor', :hours_ago => 48)).to eq(10)
    end
  end

  describe '.get_lane_ids' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('workflow_queue/lane_ids?lane_ids?step=dor:accessionWF:shelve') do |env|
          [200, {}, <<-XML]
          <lanes>
            <lane id="lane1"/>
            <lane id="lane2"/>
          </lanes>
          XML
        end
      end
    end

    it 'returns the lane ids for a given workflow step' do
      expect(subject.get_lane_ids('dor', 'accessionWF', 'shelve')).to eq(%w(lane1 lane2))
    end
  end
end
