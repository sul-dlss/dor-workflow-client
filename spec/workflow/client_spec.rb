# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Workflow::Client do
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

  let(:mock_logger) { double('Logger', info: true, debug: true, warn: true) }

  before do
    @repo  = 'dor'
    @druid = 'druid:123'
  end

  let(:client) { described_class.new connection: mock_http_connection, logger: mock_logger }

  describe '#connection' do
    subject(:conn) { client.requestor.connection }
    let(:client) { described_class.new url: 'http://example.com', timeout: 99, logger: mock_logger }

    it 'has a timeout' do
      expect(conn).to be_a(Faraday::Connection)
      expect(conn.options.timeout).to eq(99)
      expect(conn.options.open_timeout).to eq(99)
    end

    it 'has a user_agent' do
      expect(conn.headers).to include('User-Agent' => /dor-workflow-client \d+\.\d+\.\d+/)
    end

    it 'defaults to using the flat params encoder' do
      expect(conn.options.params_encoder).to eq Faraday::FlatParamsEncoder
    end
  end

  describe '#create_workflow' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("objects/#{@druid}/workflows/etdSubmitWF") { |_env| [201, {}, ''] }
        stub.post("objects/#{@druid}/workflows/raiseException") { |_env| raise 'broken' }
        stub.post("objects/#{@druid}/workflows/laneIdWF?lane-id=foo_lane") { |_env| [201, {}, ''] }
        stub.post("objects/#{@druid}/workflows/versionWF?version=2") { |_env| [201, {}, ''] }
      end
    end

    before do
      allow(Deprecation).to receive(:warn)
    end

    it 'should request the workflow by name and return the URL to the workflow' do
      client.create_workflow(@repo, @druid, 'etdSubmitWF', wf_xml)
      expect(Deprecation).to have_received(:warn)
    end

    it 'should raise on an unexpected Exception' do
      expect { client.create_workflow(@repo, @druid, 'raiseException', wf_xml) }.to raise_error(Exception, 'broken')
      expect(Deprecation).to have_received(:warn)
    end

    it 'sets the lane_id param if provided in options hash' do
      client.create_workflow(@repo, @druid, 'laneIdWF', wf_xml, lane_id: 'foo_lane')
      expect(Deprecation).to have_received(:warn)
    end
  end

  describe '#create_workflow_by_name' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("objects/#{@druid}/workflows/etdSubmitWF") { |_env| [201, {}, ''] }
        stub.post("objects/#{@druid}/workflows/raiseException") { |_env| raise 'broken' }
        stub.post("objects/#{@druid}/workflows/laneIdWF?lane-id=foo_lane") { |_env| [201, {}, ''] }
        stub.post("objects/#{@druid}/workflows/versionWF?version=2") { |_env| [201, {}, ''] }
      end
    end

    it 'should request the workflow by name and return the URL to the workflow' do
      client.create_workflow_by_name(@druid, 'etdSubmitWF')
    end

    it 'should raise on an unexpected Exception' do
      expect { client.create_workflow_by_name(@druid, 'raiseException') }.to raise_error(Exception, 'broken')
    end

    it 'sets the lane_id param if provided in options hash' do
      client.create_workflow_by_name(@druid, 'laneIdWF', lane_id: 'foo_lane')
    end

    it 'sets the version param if provided in options hash' do
      client.create_workflow_by_name(@druid, 'versionWF', version: 2)
    end
  end

  describe '#update_workflow_status' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.put("#{@repo}/objects/#{@druid}/workflows/etdSubmitWF/registrar-approval?current-status=queued") do |_env|
          [201, {}, '{"next_steps":["submit-marc"]}']
        end

        stub.put("#{@repo}/objects/#{@druid}/workflows/etdSubmitWF/registrar-approval") do |env|
          expect(env.body).to eq "<?xml version=\"1.0\"?>\n<process name=\"registrar-approval\" status=\"completed\" elapsed=\"0\" note=\"annotation\" version=\"2\" laneId=\"lane2\"/>\n"
          [201, {}, '{"next_steps":["submit-marc"]}']
        end

        stub.put("#{@repo}/objects/#{@druid}/workflows/errorWF/registrar-approval") do |_env|
          [400, {}, '']
        end
      end
    end
    before do
      allow(Deprecation).to receive(:warn)
    end

    it 'should update workflow status and return true if successful' do
      expect(client.update_workflow_status(@repo, @druid, 'etdSubmitWF', 'registrar-approval', 'completed', version: 2, note: 'annotation', lane_id: 'lane2')).to be_kind_of Dor::Workflow::Response::Update
    end

    it 'should return false if the PUT to the DOR workflow service throws an exception' do
      expect { client.update_workflow_status(@repo, @druid, 'errorWF', 'registrar-approval', 'completed') }.to raise_error(Dor::WorkflowException, /status 400/)
    end

    it 'performs a conditional update when current-status is passed as a parameter' do
      expect(mock_http_connection).to receive(:put).with("#{@repo}/objects/#{@druid}/workflows/etdSubmitWF/registrar-approval?current-status=queued").and_call_original

      expect(client.update_workflow_status(@repo, @druid, 'etdSubmitWF', 'registrar-approval', 'completed', version: 2, note: 'annotation', lane_id: 'lane1', current_status: 'queued')).to be_kind_of Dor::Workflow::Response::Update
    end

    it 'should throw exception if invalid status provided' do
      expect { client.update_workflow_status(@repo, @druid, 'accessionWF', 'publish', 'NOT_VALID_STATUS') }.to raise_error(ArgumentError)
    end
  end

  describe '#update_workflow_error_status' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.put("objects/#{@druid}/workflows/etdSubmitWF/reader-approval") do |env|
          expect(env.body).to match(/status="error" errorMessage="Some exception" errorText="The optional stacktrace"/)
          [201, {}, '{"next_steps":["submit-marc"]}']
        end

        stub.put("objects/#{@druid}/workflows/errorWF/reader-approval") do |_env|
          [400, {}, '']
        end
      end
    end

    before do
      allow(Deprecation).to receive(:warn)
    end

    it 'should update workflow status to error and return true if successful' do
      client.update_workflow_error_status(@repo, @druid, 'etdSubmitWF', 'reader-approval', 'Some exception', error_text: 'The optional stacktrace')
    end
    it 'should return false if the PUT to the DOR workflow service throws an exception' do
      expect { client.update_workflow_error_status(@repo, @druid, 'errorWF', 'reader-approval', 'completed') }.to raise_error(Dor::WorkflowException, /status 400/)
    end
  end

  describe '#workflow_template' do
    subject(:workflow_template) { client.workflow_template('etdSubmitWF') }

    let(:workflow_template_client) { instance_double Dor::Workflow::Client::WorkflowTemplate, retrieve: 'data' }

    before do
      allow(Dor::Workflow::Client::WorkflowTemplate).to receive(:new).and_return(workflow_template_client)
    end

    it 'delegates to the client' do
      expect(workflow_template).to eq 'data'
      expect(workflow_template_client).to have_received(:retrieve).with('etdSubmitWF')
    end
  end

  describe '#workflow_templates' do
    subject(:workflow_templates) { client.workflow_templates }

    let(:workflow_template_client) { instance_double Dor::Workflow::Client::WorkflowTemplate, all: 'data' }

    before do
      allow(Dor::Workflow::Client::WorkflowTemplate).to receive(:new).and_return(workflow_template_client)
    end

    it 'delegates to the client' do
      expect(workflow_templates).to eq 'data'
      expect(workflow_template_client).to have_received(:all)
    end
  end

  describe '#templates' do
    subject(:templates) { client.templates }

    it 'returns the template client' do
      expect(templates).to be_instance_of Dor::Workflow::Client::WorkflowTemplate
    end
  end

  describe '#workflow_status' do
    let(:repo) { @repo }
    let(:druid) { @druid }
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/objects/#{druid}/workflows/#{workflow_name}") do |_env|
          response
        end
      end
    end

    subject { client.workflow_status(druid: druid, workflow: workflow_name, process: step_name) }
    let(:step_name) { 'registrar-approval' }
    let(:workflow_name) { 'etdSubmitWF' }
    let(:status) { 200 }
    let(:response) do
      [status, {}, xml]
    end
    let(:xml) { '' }

    context 'when repo is provided' do
      before do
        allow(Deprecation).to receive(:warn)
      end
      subject { client.workflow_status(repo: repo, druid: druid, workflow: workflow_name, process: step_name) }

      context 'when a single result is returned' do
        let(:xml) do
          '<workflow><process name="registrar-approval" status="completed" /></workflow>'
        end

        it 'returns status as a string' do
          expect(subject).to eq('completed')
        end
      end
    end

    context 'with positional arguments' do
      before do
        allow(Deprecation).to receive(:warn)
      end
      subject { client.workflow_status(repo, druid, workflow_name, step_name) }

      context 'when a single result is returned' do
        let(:xml) do
          '<workflow><process name="registrar-approval" status="completed" /></workflow>'
        end

        it 'returns status as a string' do
          expect(subject).to eq('completed')
        end
      end
    end

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

  describe '#workflow_xml' do
    before do
      allow(Deprecation).to receive(:warn)
    end
    context 'with positional args' do
      subject(:workflow_xml) { client.workflow_xml('dor', 'druid:123', workflow) }

      context 'when a workflow name is provided' do
        let(:workflow) { 'etdSubmitWF' }
        let(:xml) { '<workflow id="etdSubmitWF"><process name="registrar-approval" status="completed" /></workflow>' }
        let(:stubs) do
          Faraday::Adapter::Test::Stubs.new do |stub|
            stub.get('dor/objects/druid:123/workflows/etdSubmitWF') do |_env|
              [200, {}, xml]
            end
          end
        end

        it 'returns the xml for a given repository, druid, and workflow' do
          expect(workflow_xml).to eq(xml)
        end
      end

      context 'when no workflow name is provided' do
        let(:workflow) { nil }

        it 'raises an error' do
          expect { workflow_xml }.to raise_error ArgumentError
        end
      end
    end
    context 'with keyword args' do
      subject(:workflow_xml) { client.workflow_xml(druid: 'druid:123', workflow: workflow) }

      context 'when a repo is provided' do
        subject(:workflow_xml) { client.workflow_xml(repo: 'dor', druid: 'druid:123', workflow: workflow) }

        let(:workflow) { 'etdSubmitWF' }
        let(:xml) { '<workflow id="etdSubmitWF"><process name="registrar-approval" status="completed" /></workflow>' }
        let(:stubs) do
          Faraday::Adapter::Test::Stubs.new do |stub|
            stub.get('dor/objects/druid:123/workflows/etdSubmitWF') do |_env|
              [200, {}, xml]
            end
          end
        end

        it 'returns the xml for a given repository, druid, and workflow' do
          expect(workflow_xml).to eq(xml)
        end
      end

      context 'when a workflow name is provided' do
        let(:workflow) { 'etdSubmitWF' }
        let(:xml) { '<workflow id="etdSubmitWF"><process name="registrar-approval" status="completed" /></workflow>' }
        let(:stubs) do
          Faraday::Adapter::Test::Stubs.new do |stub|
            stub.get('/objects/druid:123/workflows/etdSubmitWF') do |_env|
              [200, {}, xml]
            end
          end
        end

        it 'returns the xml for a given repository, druid, and workflow' do
          expect(workflow_xml).to eq(xml)
        end
      end

      context 'when no workflow name is provided' do
        let(:workflow) { nil }

        it 'raises an error' do
          expect { workflow_xml }.to raise_error ArgumentError
        end
      end
    end
  end

  describe '#all_workflows_xml' do
    subject(:all_workflows_xml) { client.all_workflows_xml('druid:123') }

    let(:workflow) { 'etdSubmitWF' }
    let(:xml) do
      <<~XML
        <workflows>
        <workflow id="etdSubmitWF"><process name="registrar-approval" status="completed" /></workflow>
        <workflow id="etdSubmitWF"><process name="registrar-approval" status="completed" /></workflow>
        </workflows>
      XML
    end
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('objects/druid:123/workflows') do |_env|
          [200, {}, xml]
        end
      end
    end

    it 'returns the xml for a given druid' do
      expect(all_workflows_xml).to eq(xml)
    end
  end

  describe '#workflows' do
    let(:xml) { '<workflow id="accessionWF"><process name="publish" status="completed" /></workflow>' }
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/objects/#{@druid}/workflows/") do |_env|
          [200, {}, xml]
        end
      end
    end

    it 'returns the workflows associated with druid' do
      expect(client.workflows(@druid)).to eq(['accessionWF'])
    end
  end

  describe '#lifecycle' do
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
      expect(client.lifecycle('dor', 'druid:123', 'released').beginning_of_day).to eq(Time.parse('2010-06-15T16:08:58-0700').beginning_of_day)
    end

    it "returns nil if the milestone hasn't been reached yet" do
      expect(client.lifecycle('dor', 'druid:abc', 'inprocess')).to be_nil
    end
  end

  describe '#active_lifecycle' do
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
      expect(client.active_lifecycle('dor', @druid, 'released').beginning_of_day).to eq(Time.parse('2010-06-15T16:08:58-0700').beginning_of_day)
    end

    it 'handles missing lifecycle' do
      expect(client.active_lifecycle('dor', @druid, 'NOT_FOUND')).to be_nil
    end
  end

  context '#objects_for_workstep' do
    before(:all) do
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
        expect(client.objects_for_workstep(@completed, @waiting, 'default', default_repository: @repository, default_workflow: @workflow)).to eq(['druid:ab123de4567', 'druid:ab123de9012'])
      end
    end

    describe 'a query with TWO steps completed and one waiting' do
      it 'creates the URI string with the two completed steps correctly' do
        second_completed = 'google-convert'
        xml = %(<objects count="1"><object id="druid:ab123de4567"/><object id="druid:ab123de9012"/></objects>)
        allow(mock_http_connection).to receive(:get).with("workflow_queue?waiting=#{@repository}:#{@workflow}:#{@waiting}&completed=#{@repository}:#{@workflow}:#{@completed}&completed=#{@repository}:#{@workflow}:#{second_completed}&lane-id=default").and_return(double(Faraday::Response, body: xml))
        expect(client.objects_for_workstep([@completed, second_completed], @waiting, 'default', default_repository: @repository, default_workflow: @workflow)).to eq(['druid:ab123de4567', 'druid:ab123de9012'])
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
          expect(client.objects_for_workstep(*args)).to eq(['druid:ab123de4567', 'druid:ab123de9012'])
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
          expect(client.objects_for_workstep(@qualified_completed, @qualified_waiting)).to eq(['druid:ab123de4567'])
        end
        it 'without any completed steps, only waiting' do
          allow(mock_http_connection).to receive(:get).with("workflow_queue?waiting=#{@qualified_waiting}&lane-id=default").and_return(double(Faraday::Response, body: @xml))
          expect(client.objects_for_workstep(nil, @qualified_waiting)).to eq(['druid:ab123de4567'])
        end
        it 'same but with lane_id' do
          allow(mock_http_connection).to receive(:get).with("workflow_queue?waiting=#{@qualified_waiting}&lane-id=lane1").and_return(double(Faraday::Response, body: @xml))
          expect(client.objects_for_workstep(nil, @qualified_waiting, 'lane1')).to eq(['druid:ab123de4567'])
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
      expect(client.objects_for_workstep(@completed, @waiting, 'default', default_repository: @repository, default_workflow: @workflow)).to eq([])
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

    describe 'errored_objects_for_workstep' do
      it 'returns error messages for errored objects' do
        expect(client.errored_objects_for_workstep(@workflow, @step, @repository)).to eq('druid:ab123cd4567' => 'This is an error message')
      end
    end

    describe 'count_errored_for_workstep' do
      it 'counts how many steps are errored out' do
        expect(client.count_errored_for_workstep(@workflow, @step, @repository)).to eq(1)
      end
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
      expect(client.count_queued_for_workstep(@workflow, @step, @repository)).to eq(1)
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
      expect(client.count_objects_in_step(@workflow, @step, @type, @repository)).to eq(1)
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
      client.delete_workflow(@repo, @druid, 'accessionWF')
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
      client.close_version(@repo, @druid)
    end

    it 'optionally prevents creation of accessionWF' do
      expect(mock_http_connection).to receive(:post).with('dor/objects/druid:123/versionClose?create-accession=false').and_call_original
      client.close_version(@repo, @druid, false)
    end
  end

  describe '.stale_queued_workflows' do
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
      ah = client.stale_queued_workflows 'dor', hours_ago: 24, limit: 100
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
      expect(client.count_stale_queued_workflows('dor', hours_ago: 48)).to eq(10)
    end
  end

  describe '.lane_ids' do
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
      expect(client.lane_ids('dor', 'accessionWF', 'shelve')).to eq(%w[lane1 lane2])
    end
  end
end
