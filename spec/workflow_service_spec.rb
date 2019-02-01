# frozen_string_literal: true

require 'spec_helper'

describe Dor::WorkflowService do
  let(:wf_xml) do
    <<-EOXML
    <workflow id="etdSubmitWF">
         <process name="register-object" status="completed" attempts="1" />
         <process name="submit" status="waiting" />
         <process name="reader-approval" status="waiting" />
         <process name="registrar-approval" status="waiting" />
         <process name="start-accession" status="waiting" />
    </workflow>
    EOXML
  end

  let(:wf_xml_label) do
    <<~EOXML
      <?xml version="1.0"?>
      <workflow id="etdSubmitWF">
         <process name="register-object" status="completed" attempts="1" laneId="default"/>
         <process name="submit" status="waiting" laneId="default"/>
         <process name="reader-approval" status="waiting" laneId="default"/>
         <process name="registrar-approval" status="waiting" laneId="default"/>
         <process name="start-accession" status="waiting" laneId="default"/>
      </workflow>
    EOXML
  end

  let(:stubs) do
    Faraday::Adapter::Test::Stubs.new
  end

  let(:mock_http_connection) do
    Faraday.new(url: 'http://example.com/') do |builder|
      builder.use Faraday::Response::RaiseError
      builder.options.params_encoder = Faraday::FlatParamsEncoder

      builder.adapter :test, stubs
    end
  end

  before(:each) do
    @repo  = 'dor'
    @druid = 'druid:123'
    @mock_logger = double('Logger')

    allow(@mock_logger).to receive(:info)  # silence log output
    allow(@mock_logger).to receive(:debug) # silence log output
    allow(@mock_logger).to receive(:warn) # silence log output
    allow(Dor::WorkflowService).to receive(:default_logger).and_return(@mock_logger)

    Dor::WorkflowService.configure mock_http_connection
  end

  describe '#configure' do
    it 'should handle a string and timeout' do
      conn = Dor::WorkflowService.configure 'http://externalhost/', timeout: 99
      expect(conn).to be_a(Faraday::Connection)
      expect(conn.options.timeout).to eq(99)
      expect(conn.options.open_timeout).to eq(99)
    end
  end

  describe '#create_workflow' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.put("#{@repo}/objects/#{@druid}/workflows/etdSubmitWF") { |_env| [201, {}, ''] }
        stub.put("#{@repo}/objects/#{@druid}/workflows/noCreateDsWF?create-ds=false") { |_env| [201, {}, ''] }
        stub.put("#{@repo}/objects/#{@druid}/workflows/httpException") { |_env| [418, {}, "I'm A Teapot"] }
        stub.put("#{@repo}/objects/#{@druid}/workflows/raiseException") { |_env| raise 'broken' }
      end
    end

    it 'should pass workflow xml to the DOR workflow service and return the URL to the workflow' do
      Dor::WorkflowService.create_workflow(@repo, @druid, 'etdSubmitWF', wf_xml)
    end

    it 'should log an error and retry upon a targetted Faraday exception' do
      expect(@mock_logger).to receive(:warn).with(/\[Attempt 1\] Faraday::ClientError: the server responded with status 418/)
      expect { Dor::WorkflowService.create_workflow(@repo, @druid, 'httpException', wf_xml) }.to raise_error Dor::WorkflowException
    end

    it 'should raise on an unexpected Exception' do
      expect { Dor::WorkflowService.create_workflow(@repo, @druid, 'raiseException', wf_xml) }.to raise_error(Exception, 'broken')
    end

    it 'sets the create-ds param to the value of the passed in options hash' do
      Dor::WorkflowService.create_workflow(@repo, @druid, 'noCreateDsWF', wf_xml, create_ds: false)
    end

    it 'adds lane_id attributes to all steps if passed in as an option' do
      skip 'test not implemented'
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
      expect(Dor::WorkflowService.send(:add_lane_id_to_workflow_xml, 'lane1', wf_xml)).to be_equivalent_to(expected)
    end
  end

  describe '#update_workflow_status' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.put("#{@repo}/objects/#{@druid}/workflows/etdSubmitWF/reader-approval?current-status=queued") do |_env|
          [201, {}, '']
        end

        stub.put("#{@repo}/objects/#{@druid}/workflows/etdSubmitWF/reader-approval") do |env|
          expect(env.body).to eq "<?xml version=\"1.0\"?>\n<process name=\"reader-approval\" status=\"completed\" elapsed=\"0\" note=\"annotation\" version=\"2\" laneId=\"lane2\"/>\n"
          [201, {}, '']
        end

        stub.put("#{@repo}/objects/#{@druid}/workflows/errorWF/reader-approval") do |_env|
          [400, {}, '']
        end
      end
    end

    it 'should update workflow status and return true if successful' do
      expect(Dor::WorkflowService.update_workflow_status(@repo, @druid, 'etdSubmitWF', 'reader-approval', 'completed', version: 2, note: 'annotation', lane_id: 'lane2')).to be true
    end

    it 'should return false if the PUT to the DOR workflow service throws an exception' do
      expect { Dor::WorkflowService.update_workflow_status(@repo, @druid, 'errorWF', 'reader-approval', 'completed') }.to raise_error(Dor::WorkflowException, /status 400/)
    end

    it 'performs a conditional update when current-status is passed as a parameter' do
      expect(mock_http_connection).to receive(:put).with("#{@repo}/objects/#{@druid}/workflows/etdSubmitWF/reader-approval?current-status=queued").and_call_original

      expect(Dor::WorkflowService.update_workflow_status(@repo, @druid, 'etdSubmitWF', 'reader-approval', 'completed', version: 2, note: 'annotation', lane_id: 'lane1', current_status: 'queued')).to be true
    end

    it 'should throw exception if invalid status provided' do
      expect { Dor::WorkflowService.update_workflow_status(@repo, @druid, 'accessionWF', 'publish', 'NOT_VALID_STATUS') }.to raise_error(ArgumentError)
    end
  end

  describe '#update_workflow_error_status' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.put("#{@repo}/objects/#{@druid}/workflows/etdSubmitWF/reader-approval") do |env|
          expect(env.body).to match /status="error" errorMessage="Some exception" errorText="The optional stacktrace"/
          [201, {}, '']
        end

        stub.put("#{@repo}/objects/#{@druid}/workflows/errorWF/reader-approval") do |_env|
          [400, {}, '']
        end
      end
    end

    it 'should update workflow status to error and return true if successful' do
      Dor::WorkflowService.update_workflow_error_status(@repo, @druid, 'etdSubmitWF', 'reader-approval', 'Some exception', error_text: 'The optional stacktrace')
    end
    it 'should return false if the PUT to the DOR workflow service throws an exception' do
      expect { Dor::WorkflowService.update_workflow_status(@repo, @druid, 'errorWF', 'reader-approval', 'completed') }.to raise_error(Dor::WorkflowException, /status 400/)
    end
  end

  describe '#get_workflow_status' do
    let(:repo) { @repo }
    let(:druid) { @druid }
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("#{repo}/objects/#{druid}/workflows/#{workflow_name}") do |_env|
          response
        end
      end
    end

    subject { Dor::WorkflowService.get_workflow_status(repo, druid, workflow_name, step_name) }
    let(:step_name) { 'registrar-approval' }
    let(:workflow_name) { 'etdSubmitWF' }
    let(:status) { 200 }
    let(:response) do
      [status, {}, xml]
    end
    let(:xml) { '' }

    context 'when a single result is returned' do
      let(:xml) do
        '<workflow><process name="registrar-approval" status="completed" /></workflow>'
      end

      it 'returns status as a string' do
        expect(subject).to eq('completed')
      end
    end

    context 'when a multiple versions are returned' do
      let(:xml) do
        '<workflow><process name="registrar-approval" version="1" status="completed" />
          <process name="registrar-approval" version="2" status="waiting" /></workflow>'
      end

      it 'returns the status for the highest version' do
        expect(subject).to eq('waiting')
      end
    end

    context 'when it fails for any reason' do
      let(:status) { 404 }

      it 'throws an exception' do
        expect { subject }.to raise_error Dor::WorkflowException
      end
    end

    context 'when it cannot parse the response' do
      let(:xml) do
        'something not xml'
      end

      it 'throws an exception' do
        expect { subject }.to raise_error Dor::WorkflowException, "Unable to parse response:\nsomething not xml"
      end
    end

    context 'when the workflow/process combination doesnt exist' do
      let(:xml) do
        '<workflow><process name="registrar-approval" status="completed" /></workflow>'
      end
      let(:step_name) { 'publish' }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end
  end

  describe '#get_workflow_xml' do
    let(:xml) { '<workflow id="etdSubmitWF"><process name="registrar-approval" status="completed" /></workflow>' }
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('dor/objects/druid:123/workflows/etdSubmitWF') do |_env|
          [200, {}, xml]
        end
      end
    end

    it 'returns the xml for a given repository, druid, and workflow' do
      expect(Dor::WorkflowService.get_workflow_xml('dor', 'druid:123', 'etdSubmitWF')).to eq(xml)
    end
  end

  describe '#get_workflows' do
    let(:xml) { '<workflow id="accessionWF"><process name="publish" status="completed" /></workflow>' }
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("dor/objects/#{@druid}/workflows/") do |_env|
          [200, {}, xml]
        end
      end
    end

    it 'returns the workflows associated with druid' do
      expect(Dor::WorkflowService.get_workflows(@druid)).to eq(['accessionWF'])
    end
  end

  describe '#get_lifecycle' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('dor/objects/druid:123/lifecycle') do |_env|
          [200, {}, <<-EOXML]
            <lifecycle objectId="druid:ct011cv6501">
                <milestone date="2010-04-27T11:34:17-0700">registered</milestone>
                <milestone date="2010-04-29T10:12:51-0700">inprocess</milestone>
                <milestone date="2010-06-15T16:08:58-0700">released</milestone>
            </lifecycle>
          EOXML
        end

        stub.get('dor/objects/druid:abc/lifecycle') do |_env|
          [200, {}, <<-EOXML]
            <lifecycle />
          EOXML
        end
      end
    end

    it 'returns a Time object reprenting when the milestone was reached' do
      expect(Dor::WorkflowService.get_lifecycle('dor', 'druid:123', 'released').beginning_of_day).to eq(Time.parse('2010-06-15T16:08:58-0700').beginning_of_day)
    end

    it "returns nil if the milestone hasn't been reached yet" do
      expect(Dor::WorkflowService.get_lifecycle('dor', 'druid:abc', 'inprocess')).to be_nil
    end
  end

  describe '#get_active_lifecycle' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("dor/objects/#{@druid}/lifecycle") do |_env|
          [200, {}, <<-EOXML]
            <lifecycle objectId="#{@druid}">
                <milestone date="2010-04-27T11:34:17-0700">registered</milestone>
                <milestone date="2010-04-29T10:12:51-0700">inprocess</milestone>
                <milestone date="2010-06-15T16:08:58-0700">released</milestone>
            </lifecycle>
          EOXML
        end

        stub.get("dor/objects/#{@druid}/lifecycle") do |_env|
          [200, {}, <<-EOXML]
            <lifecycle />
          EOXML
        end
      end
    end

    it 'parses out the active lifecycle' do
      expect(Dor::WorkflowService.get_active_lifecycle('dor', @druid, 'released').beginning_of_day).to eq(Time.parse('2010-06-15T16:08:58-0700').beginning_of_day)
    end

    it 'handles missing lifecycle' do
      expect(Dor::WorkflowService.get_active_lifecycle('dor', @druid, 'NOT_FOUND')).to be_nil
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
        stub.get("workflow_queue?waiting=#{@repository}:#{@workflow}:#{@waiting}&completed=#{@repository}:#{@workflow}:#{@completed}&lane-id=default") do |_env|
          [200, {}, '<objects count="1"><object id="druid:ab123de4567"/><object id="druid:ab123de9012"/></objects>']
        end
      end
    end

    describe 'a query with one step completed and one waiting' do
      it 'creates the URI string with only the one completed step' do
        expect(Dor::WorkflowService.get_objects_for_workstep(@completed, @waiting, 'default', default_repository: @repository, default_workflow: @workflow)).to eq(['druid:ab123de4567', 'druid:ab123de9012'])
      end
    end

    describe 'a query with TWO steps completed and one waiting' do
      it 'creates the URI string with the two completed steps correctly' do
        second_completed = 'google-convert'
        xml = %(<objects count="1"><object id="druid:ab123de4567"/><object id="druid:ab123de9012"/></objects>)
        allow(mock_http_connection).to receive(:get).with("workflow_queue?waiting=#{@repository}:#{@workflow}:#{@waiting}&completed=#{@repository}:#{@workflow}:#{@completed}&completed=#{@repository}:#{@workflow}:#{second_completed}&lane-id=default").and_return(double(Faraday::Response, body: xml))
        expect(Dor::WorkflowService.get_objects_for_workstep([@completed, second_completed], @waiting, 'default', default_repository: @repository, default_workflow: @workflow)).to eq(['druid:ab123de4567', 'druid:ab123de9012'])
      end
    end

    context 'a query using qualified workflow names for completed and waiting' do
      before :each do
        @qualified_waiting   = "#{@repository}:#{@workflow}:#{@waiting}"
        @qualified_completed = "#{@repository}:#{@workflow}:#{@completed}"
      end

      RSpec.shared_examples 'lane-aware' do
        it 'creates the URI string with the two completed steps across repositories correctly' do
          qualified_completed2 = 'sdr:sdrIngestWF:complete-deposit'
          qualified_completed3 = 'sdr:sdrIngestWF:ingest-transfer'
          xml = %(<objects count="2"><object id="druid:ab123de4567"/><object id="druid:ab123de9012"/></objects>)
          allow(mock_http_connection).to receive(:get).with("workflow_queue?waiting=#{@qualified_waiting}&completed=#{@qualified_completed}&completed=#{qualified_completed2}&completed=#{qualified_completed3}&lane-id=#{laneid}").and_return(double(Faraday::Response, body: xml))
          args = [[@qualified_completed, qualified_completed2, qualified_completed3], @qualified_waiting]
          args << laneid if laneid != 'default'
          expect(Dor::WorkflowService.get_objects_for_workstep(*args)).to eq(['druid:ab123de4567', 'druid:ab123de9012'])
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
          @xml = %(<objects count="1"><object id="druid:ab123de4567"/></objects>)
        end
        it 'with only one completed step passed in as a String' do
          allow(mock_http_connection).to receive(:get).with("workflow_queue?waiting=#{@qualified_waiting}&completed=#{@qualified_completed}&lane-id=default").and_return(double(Faraday::Response, body: @xml))
          expect(Dor::WorkflowService.get_objects_for_workstep(@qualified_completed, @qualified_waiting)).to eq(['druid:ab123de4567'])
        end
        it 'without any completed steps, only waiting' do
          allow(mock_http_connection).to receive(:get).with("workflow_queue?waiting=#{@qualified_waiting}&lane-id=default").and_return(double(Faraday::Response, body: @xml))
          expect(Dor::WorkflowService.get_objects_for_workstep(nil, @qualified_waiting)).to eq(['druid:ab123de4567'])
        end
        it 'same but with lane_id' do
          allow(mock_http_connection).to receive(:get).with("workflow_queue?waiting=#{@qualified_waiting}&lane-id=lane1").and_return(double(Faraday::Response, body: @xml))
          expect(Dor::WorkflowService.get_objects_for_workstep(nil, @qualified_waiting, 'lane1')).to eq(['druid:ab123de4567'])
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
        stub.get("workflow_queue?waiting=#{@repository}:#{@workflow}:#{@waiting}&completed=#{@repository}:#{@workflow}:#{@completed}&lane-id=default") do |_env|
          [200, {}, '<objects count="0"/>']
        end
      end
    end

    it 'returns an empty list if it encounters an empty workflow queue' do
      expect(Dor::WorkflowService.get_objects_for_workstep(@completed, @waiting, 'default', default_repository: @repository, default_workflow: @workflow)).to eq([])
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
        stub.get("/workflow_queue?error=#{@step}&repository=#{@repository}&workflow=#{@workflow}") do |_env|
          [200, {}, <<-EOXML]
            <objects count="1">
               <object id="druid:ab123cd4567" errorMessage="This is an error message"/>
             </objects>
          EOXML
        end
      end
    end

    it 'returns error messages for errored objects' do
      expect(Dor::WorkflowService.get_errored_objects_for_workstep(@workflow, @step, @repository)).to eq('druid:ab123cd4567' => 'This is an error message')
    end

    it 'counts how many steps are errored out' do
      expect(Dor::WorkflowService.count_errored_for_workstep(@workflow, @step, @repository)).to eq(1)
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
        stub.get("/workflow_queue?queued=#{@step}&repository=#{@repository}&workflow=#{@workflow}") do |_env|
          [200, {}, <<-EOXML]
            <objects count="1">
               <object id="druid:ab123cd4567"/>
             </objects>
          EOXML
        end
      end
    end

    it 'counts how many steps are errored out' do
      expect(Dor::WorkflowService.count_queued_for_workstep(@workflow, @step, @repository)).to eq(1)
    end
  end

  describe '#count_archived_for_workflow' do
    before(:all) do
      @repository = 'dor'
      @workflow   = 'accessionWF'
    end

    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/workflow_archive?repository=#{@repository}&workflow=#{@workflow}&count-only=true") do |_env|
          [200, {}, <<-EOXML]
            <objects count="20" />
          EOXML
        end
      end
    end

    it 'counts how many workflows are archived' do
      expect(Dor::WorkflowService.count_archived_for_workflow(@workflow, @repository)).to eq(20)
    end
  end

  describe '#count_objects_in_step' do
    before(:all) do
      @workflow   = 'sdrIngestWF'
      @step       = 'start-ingest'
      @type       = 'waiting'
      @repository = 'sdr'
    end

    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/workflow_queue?repository=#{@repository}&workflow=#{@workflow}&#{@type}=#{@step}") do |_env|
          [200, {}, <<-EOXML]
            <objects count="1">
              <object id="druid:oo000ra0001" url="null/fedora/objects/druid:oo000ra0001"/>
            </objects>
          EOXML
        end
      end
    end

    it 'counts how many objects are at the type of step' do
      expect(Dor::WorkflowService.count_objects_in_step(@workflow, @step, @type, @repository)).to eq(1)
    end
  end

  describe '#delete_workflow' do
    let(:url) { "#{@repo}/objects/#{@druid}/workflows/accessionWF" }

    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.delete(url) { |_env| [202, {}, ''] }
      end
    end

    it 'sends a delete request to the workflow service' do
      expect(mock_http_connection).to receive(:delete).with(url).and_call_original
      Dor::WorkflowService.delete_workflow(@repo, @druid, 'accessionWF')
    end
  end
  describe 'get_milestones' do
    it 'should include the version in with the milestones' do
      xml = '<?xml version="1.0" encoding="UTF-8"?><lifecycle objectId="druid:gv054hp4128"><milestone date="2012-01-26T21:06:54-0800" version="2">published</milestone></lifecycle>'
      xml = Nokogiri::XML(xml)
      allow(Dor::WorkflowService).to receive(:query_lifecycle).and_return(xml)
      milestones = Dor::WorkflowService.get_milestones(@repo, @druid)
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
      allow(Dor::WorkflowService).to receive(:get_workflow_xml) { xml }
      expect(Deprecation).to receive(:warn)
      expect(Dor::WorkflowService.get_active_workflows('dor', 'druid:mw971zk1113')).to eq(['accessionWF'])
    end
  end

  describe '.workflow' do
    let(:xml) do
      <<~XML
        <workflow repository="dor" objectId="druid:mw971zk1113" id="accessionWF">
          <process laneId="default" lifecycle="submitted" elapsed="0.0" attempts="1" datetime="2013-02-18T15:08:10-0800" status="completed" name="start-accession"/>
        </workflow>
      XML
    end
    before do
      allow(Dor::WorkflowService).to receive(:get_workflow_xml) { xml }
    end

    it 'it returns a workflow' do
      expect(Dor::WorkflowService.workflow(pid: 'druid:mw971zk1113', workflow_name: 'accessionWF')).to be_kind_of Dor::Workflow::Response::Workflow
    end
  end

  describe '#close_version' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post('dor/objects/druid:123/versionClose?create-accession=false') do |_env|
          [202, {}, '']
        end

        stub.post('dor/objects/druid:123/versionClose') do |_env|
          [202, {}, '']
        end
      end
    end

    let(:url) { 'dor/objects/druid:123/versionClose' }
    it 'calls the versionClose endpoint with druid' do
      Dor::WorkflowService.close_version(@repo, @druid)
    end

    it 'optionally prevents creation of accessionWF' do
      expect(mock_http_connection).to receive(:post).with('dor/objects/druid:123/versionClose?create-accession=false').and_call_original
      Dor::WorkflowService.close_version(@repo, @druid, false)
    end
  end

  describe '.get_stale_queued_workflows' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('workflow_queue/all_queued?repository=dor&hours-ago=24&limit=100') do |_env|
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
      ah = Dor::WorkflowService.get_stale_queued_workflows 'dor', hours_ago: 24, limit: 100
      expected = [
        { workflow: 'accessionWF', step: 'content-metadata', druid: 'dr:123', lane_id: 'lane1' },
        { workflow: 'assemblyWF',  step: 'jp2-create',       druid: 'dr:456', lane_id: 'lane2' }
      ]
      expect(ah).to eql(expected)
    end
  end

  describe '.count_stale_queued_workflows' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('workflow_queue/all_queued?repository=dor&hours-ago=48&count-only=true') do |_env|
          [200, {}, '<objects count="10"/>']
        end
      end
    end

    it 'returns the number of queued workflow steps' do
      expect(Dor::WorkflowService.count_stale_queued_workflows('dor', hours_ago: 48)).to eq(10)
    end
  end

  describe '.get_lane_ids' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('workflow_queue/lane_ids?lane_ids?step=dor:accessionWF:shelve') do |_env|
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
      expect(Dor::WorkflowService.get_lane_ids('dor', 'accessionWF', 'shelve')).to eq(%w[lane1 lane2])
    end
  end

  describe '.workflow_resource_method' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('x?complete=a&complete=b') do |_env|
          [200, {}, 'ab']
        end
      end
    end

    it 'uses the flat params encoder' do
      response = Dor::WorkflowService.send(:send_workflow_resource_request, 'x?complete=a&complete=b')

      expect(response.body).to eq 'ab'
      expect(response.env.url.query).to eq 'complete=a&complete=b'
    end
  end

  describe '.workflow_resource' do
    before do
      Dor::WorkflowService.configure 'http://example.com'
    end

    it 'defaults to using the flat params encoder' do
      expect(Dor::WorkflowService.workflow_resource.options.params_encoder).to eq Faraday::FlatParamsEncoder
    end
  end
end
