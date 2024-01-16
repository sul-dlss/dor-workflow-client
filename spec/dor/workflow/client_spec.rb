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
  let(:client) { described_class.new connection: mock_http_connection, logger: mock_logger }

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
    @druid = 'druid:123'
  end

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

  describe '#create_workflow_by_name' do
    context 'when an unexpected exception is raised' do
      let(:stubs) do
        Faraday::Adapter::Test::Stubs.new do |stub|
          stub.post("objects/#{@druid}/workflows/raiseException") { |_env| raise 'broken' }
        end
      end

      it 'raises the error' do
        expect { client.create_workflow_by_name(@druid, 'raiseException', version: '1') }.to raise_error(Exception, 'broken')
      end
    end

    context 'when lane_id is provided' do
      let(:stubs) do
        Faraday::Adapter::Test::Stubs.new do |stub|
          stub.post("objects/#{@druid}/workflows/laneIdWF?lane-id=foo_lane&version=1") { |_env| [201, {}, ''] }
        end
      end

      it 'sets the lane_id param' do
        # if the stub isn't correct (params), it will raise an error
        expect { client.create_workflow_by_name(@druid, 'laneIdWF', lane_id: 'foo_lane', version: 1) }.not_to raise_error
      end
    end

    context 'when lane_id is not provided' do
      let(:stubs) do
        Faraday::Adapter::Test::Stubs.new do |stub|
          stub.post("objects/#{@druid}/workflows/versionWF?version=2") { |_env| [201, {}, ''] }
        end
      end

      it 'sets the version param if provided in options hash' do
        # if the stub isn't correct (options hash), it will raise an error
        expect { client.create_workflow_by_name(@druid, 'versionWF', version: 2) }.not_to raise_error
      end
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

  describe '#templates' do
    subject(:templates) { client.templates }

    it 'returns the template client' do
      expect(templates).to be_instance_of Dor::Workflow::Client::WorkflowTemplate
    end
  end

  describe '#workflow_status' do
    subject(:workflow_status) { client.workflow_status(druid: druid, workflow: workflow_name, process: step_name) }

    let(:repo) { nil }
    let(:step_name) { 'registrar-approval' }
    let(:workflow_name) { 'etdSubmitWF' }
    let(:status) { 200 }
    let(:response) do
      [status, {}, xml]
    end
    let(:xml) { '' }
    let(:druid) { @druid }
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/objects/#{druid}/workflows/#{workflow_name}") do |_env|
          response
        end
      end
    end

    context 'when a single result is returned' do
      let(:xml) do
        '<workflow><process name="registrar-approval" status="completed" /></workflow>'
      end

      it 'returns status as a string' do
        expect(workflow_status).to eq('completed')
      end
    end

    context 'when a multiple versions are returned' do
      let(:xml) do
        '<workflow><process name="registrar-approval" version="1" status="completed" />
          <process name="registrar-approval" version="2" status="waiting" /></workflow>'
      end

      it 'returns the status for the highest version' do
        expect(workflow_status).to eq('waiting')
      end
    end

    context 'when the status is not found' do
      let(:status) { 404 }

      it 'throws the missing workflow exception' do
        expect { workflow_status }.to raise_error Dor::MissingWorkflowException
      end
    end

    context 'when it fails with status other than 404' do
      let(:status) { 422 }

      it 'throws an exception' do
        expect { workflow_status }.to raise_error Dor::WorkflowException
      end
    end

    context 'when it cannot parse the response' do
      let(:xml) do
        'something not xml'
      end

      it 'throws an exception' do
        expect { workflow_status }.to raise_error Dor::WorkflowException, "Unable to parse response:\nsomething not xml"
      end
    end

    context 'when the workflow/process combination doesnt exist' do
      let(:xml) do
        '<workflow><process name="registrar-approval" status="completed" /></workflow>'
      end
      let(:step_name) { 'publish' }

      it 'returns nil' do
        expect(workflow_status).to be_nil
      end
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
        stub.get('objects/druid:123/lifecycle') do |_env|
          [200, {}, <<-EOXML]
            <lifecycle objectId="druid:ct011cv6501">
                <milestone date="2010-04-27T11:34:17-0700">registered</milestone>
                <milestone date="2010-04-29T10:12:51-0700">inprocess</milestone>
                <milestone date="2010-06-15T16:08:58-0700">released</milestone>
            </lifecycle>
          EOXML
        end

        stub.get('objects/druid:abc/lifecycle') do |_env|
          [200, {}, <<-EOXML]
            <lifecycle />
          EOXML
        end
      end
    end

    it 'returns a Time object reprenting when the milestone was reached' do
      expect(client.lifecycle(druid: 'druid:123', milestone_name: 'released').beginning_of_day).to eq(Time.parse('2010-06-15T16:08:58-0700').beginning_of_day)
    end

    it "returns nil if the milestone hasn't been reached yet" do
      expect(client.lifecycle(druid: 'druid:abc', milestone_name: 'inprocess')).to be_nil
    end
  end

  describe '#active_lifecycle' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("objects/#{@druid}/lifecycle") do |_env|
          [200, {}, <<-EOXML]
            <lifecycle objectId="#{@druid}">
                <milestone date="2010-04-27T11:34:17-0700">registered</milestone>
                <milestone date="2010-04-29T10:12:51-0700">inprocess</milestone>
                <milestone date="2010-06-15T16:08:58-0700">released</milestone>
            </lifecycle>
          EOXML
        end

        stub.get("objects/#{@druid}/lifecycle") do |_env|
          [200, {}, <<-EOXML]
            <lifecycle />
          EOXML
        end
      end
    end

    it 'parses out the active lifecycle' do
      expect(client.active_lifecycle(druid: @druid, milestone_name: 'released', version: '1').beginning_of_day).to eq(Time.parse('2010-06-15T16:08:58-0700').beginning_of_day)
    end

    it 'handles missing lifecycle' do
      expect(client.active_lifecycle(druid: @druid, milestone_name: 'NOT_FOUND', version: '1')).to be_nil
    end
  end

  describe '#objects_for_workstep' do
    before do
      @workflow   = 'googleScannedBookWF'
      @completed  = 'google-download'
      @waiting    = 'process-content'
    end

    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("workflow_queue?waiting=#{@workflow}:#{@waiting}&completed=#{@workflow}:#{@completed}&lane-id=default") do |_env|
          [200, {}, '<objects count="1"><object id="druid:ab123de4567"/><object id="druid:ab123de9012"/></objects>']
        end
      end
    end

    describe 'a query with one step completed and one waiting' do
      it 'creates the URI string with only the one completed step' do
        expect(client.objects_for_workstep(@completed, @waiting, 'default', default_workflow: @workflow)).to eq(['druid:ab123de4567', 'druid:ab123de9012'])
      end
    end

    describe 'a query with TWO steps completed and one waiting' do
      it 'creates the URI string with the two completed steps correctly' do
        second_completed = 'google-convert'
        xml = %(<objects count="1"><object id="druid:ab123de4567"/><object id="druid:ab123de9012"/></objects>)
        allow(mock_http_connection).to receive(:get).with("workflow_queue?waiting=#{@workflow}:#{@waiting}&completed=#{@workflow}:#{@completed}&completed=#{@workflow}:#{second_completed}&lane-id=default").and_return(double(Faraday::Response, body: xml))
        expect(client.objects_for_workstep([@completed, second_completed], @waiting, 'default', default_workflow: @workflow)).to eq(['druid:ab123de4567', 'druid:ab123de9012'])
      end
    end

    context 'with a query using qualified workflow names for completed and waiting' do
      before do
        @qualified_waiting   = "#{@workflow}:#{@waiting}"
        @qualified_completed = "#{@workflow}:#{@completed}"
      end

      RSpec.shared_examples 'lane-aware' do
        it 'creates the URI string with the two completed steps across repositories correctly' do
          qualified_completed2 = 'sdrIngestWF:complete-deposit'
          qualified_completed3 = 'sdrIngestWF:ingest-transfer'
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

      context 'with URI string creation' do
        before do
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

  context 'when empty workflow queue' do
    before do
      @workflow   = 'googleScannedBookWF'
      @completed  = 'google-download'
      @waiting    = 'process-content'
    end

    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("workflow_queue?waiting=#{@workflow}:#{@waiting}&completed=#{@workflow}:#{@completed}&lane-id=default") do |_env|
          [200, {}, '<objects count="0"/>']
        end
      end
    end

    it 'returns an empty list if it encounters an empty workflow queue' do
      expect(client.objects_for_workstep(@completed, @waiting, 'default', default_workflow: @workflow)).to eq([])
    end
  end

  describe '#delete_workflow' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.delete(url) { |_env| [202, {}, ''] }
      end
    end
    let(:url) { "/objects/#{@druid}/workflows/accessionWF?version=5" }

    before do
      allow(mock_http_connection).to receive(:delete).with(url).and_call_original
    end

    it 'sends a delete request to the workflow service' do
      client.delete_workflow(druid: @druid, workflow: 'accessionWF', version: 5)
      expect(mock_http_connection).to have_received(:delete).with(url)
    end
  end

  describe '.lane_ids' do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get('workflow_queue/lane_ids?step=accessionWF:shelve') do |_env|
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
      expect(client.lane_ids('accessionWF', 'shelve')).to eq(%w[lane1 lane2])
    end
  end
end
