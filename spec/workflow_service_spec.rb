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

  before(:each) do
    @repo = 'dor'
    @druid = 'druid:123'

    @mock_logger = double('logger').as_null_object
    allow(Rails).to receive(:logger).and_return(@mock_logger)

    @mock_resource = double('mock_rest_client_resource')
    allow(@mock_resource).to receive(:[]).and_return(@mock_resource)
    allow(@mock_resource).to receive(:options).and_return( {} )
    allow(RestClient::Resource).to receive(:new).and_return(@mock_resource)
    Dor::WorkflowService.configure 'https://dortest.stanford.edu/workflow'
  end

  describe '#create_workflow' do
    it 'should pass workflow xml to the DOR workflow service and return the URL to the workflow' do
      expect(@mock_resource).to receive(:put).with(wf_xml_label, anything).and_return('')
      Dor::WorkflowService.create_workflow(@repo, @druid, 'etdSubmitWF', wf_xml)
    end

    it 'should log an error and return false if the PUT to the DOR workflow service throws an exception' do
      ex = Exception.new('exception thrown')
      expect(@mock_resource).to receive(:put).and_raise(ex)
      expect{ Dor::WorkflowService.create_workflow(@repo, @druid, 'etdSubmitWF', wf_xml) }.to raise_error(Exception, 'exception thrown')
    end

    it 'sets the create-ds param to the value of the passed in options hash' do
      expect(@mock_resource).to receive(:put).with(wf_xml_label, :content_type => 'application/xml',
                                                :params => {'create-ds' => false}).and_return('')
      Dor::WorkflowService.create_workflow(@repo, @druid, 'etdSubmitWF', wf_xml, :create_ds => false)
    end

    it 'adds lane_id attributes to all steps if passed in as an option' do
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
    before(:each) do
      @xml_re = /name="reader-approval"/
    end

    it 'should update workflow status and return true if successful' do
      built_xml = "<?xml version=\"1.0\"?>\n<process name=\"reader-approval\" status=\"completed\" elapsed=\"0\" note=\"annotation\" version=\"2\" laneId=\"lane2\"/>\n"
      expect(@mock_resource).to receive(:put).with(built_xml, { :content_type => 'application/xml' }).and_return('')
      expect(Dor::WorkflowService.update_workflow_status(@repo, @druid, 'etdSubmitWF', 'reader-approval', 'completed', :version => 2, :note => 'annotation', :lane_id => 'lane2')).to be true
    end

    it 'should return false if the PUT to the DOR workflow service throws an exception' do
      ex = Exception.new('exception thrown')
      expect(@mock_resource).to receive(:put).with(@xml_re, { :content_type => 'application/xml' }).and_raise(ex)
      expect{ Dor::WorkflowService.update_workflow_status(@repo, @druid, 'etdSubmitWF', 'reader-approval', 'completed') }.to raise_error(Exception, 'exception thrown')
    end

    it 'performs a conditional update when current-status is passed as a parameter' do
      expect(@mock_resource).to receive(:[]).with('dor/objects/druid:123/workflows/etdSubmitWF/reader-approval?current-status=queued')
      expect(@mock_resource).to receive(:put).with(@xml_re, { :content_type => 'application/xml' }).and_return('')
      expect(Dor::WorkflowService.update_workflow_status(@repo, @druid, 'etdSubmitWF', 'reader-approval', 'completed', :version => 2, :note => 'annotation', :lane_id => 'lane1', :current_status => 'queued')).to be true
    end
  end

  describe '#update_workflow_error_status' do
    it 'should update workflow status to error and return true if successful' do
      expect(@mock_resource).to receive(:put).with(/status="error" errorMessage="Some exception" errorText="The optional stacktrace"/, { :content_type => 'application/xml' }).and_return('')
      Dor::WorkflowService.update_workflow_error_status(@repo, @druid, 'etdSubmitWF', 'reader-approval', 'Some exception', :error_text =>'The optional stacktrace')
    end

    it 'should return false if the PUT to the DOR workflow service throws an exception' do
      ex = Exception.new('exception thrown')
      expect(@mock_resource).to receive(:put).with(/status="completed"/, { :content_type => 'application/xml' }).and_raise(ex)
      expect{ Dor::WorkflowService.update_workflow_status(@repo, @druid, 'etdSubmitWF', 'reader-approval', 'completed') }.to raise_error(Exception, 'exception thrown')
    end
  end

  describe '#get_workflow_status' do
    it 'parses workflow xml and returns status as a string' do
      expect(@mock_resource).to receive(:get).and_return('<process name="registrar-approval" status="completed" />')
      expect(Dor::WorkflowService.get_workflow_status('dor', 'druid:123', 'etdSubmitWF', 'registrar-approval')).to eq('completed')
    end

    it 'should throw an exception if it fails for any reason' do
      ex = Exception.new('exception thrown')
      expect(@mock_resource).to receive(:get).and_raise(ex)

      expect{ Dor::WorkflowService.get_workflow_status('dor', 'druid:123', 'etdSubmitWF', 'registrar-approval') }.to raise_error(Exception, 'exception thrown')
    end

    it 'should throw an exception if it cannot parse the response' do
      expect(@mock_resource).to receive(:get).and_return('something not xml')
      expect{ Dor::WorkflowService.get_workflow_status('dor', 'druid:123', 'etdSubmitWF', 'registrar-approval') }.to raise_error(Exception, "Unable to parse response:\nsomething not xml")
    end
    it 'should return nil if the workflow/process combination doesnt exist' do
      expect(@mock_resource).to receive(:get).and_return('<process name="registrar-approval" status="completed" />')
      expect(Dor::WorkflowService.get_workflow_status('dor', 'druid:123', 'accessionWF', 'publish')).to eq(nil)
    end
  end

  describe '#get_workflow_xml' do
    it 'returns the xml for a given repository, druid, and workflow' do
      xml = '<workflow id="etdSubmitWF"><process name="registrar-approval" status="completed" /></workflow>'
      expect(@mock_resource).to receive(:get).and_return(xml)
      expect(Dor::WorkflowService.get_workflow_xml('dor', 'druid:123', 'etdSubmitWF')).to eq(xml)
    end
  end

  describe '#get_lifecycle' do
    it 'returns a Time object reprenting when the milestone was reached' do
      xml = <<-EOXML
        <lifecycle objectId="druid:ct011cv6501">
            <milestone date="2010-04-27T11:34:17-0700">registered</milestone>
            <milestone date="2010-04-29T10:12:51-0700">inprocess</milestone>
            <milestone date="2010-06-15T16:08:58-0700">released</milestone>
        </lifecycle>
      EOXML
      expect(@mock_resource).to receive(:get).and_return(xml)
      expect(Dor::WorkflowService.get_lifecycle('dor', 'druid:123', 'released').beginning_of_day).to eq(Time.parse('2010-06-15T16:08:58-0700').beginning_of_day)
    end

    it "returns nil if the milestone hasn't been reached yet" do
      expect(@mock_resource).to receive(:get).and_return('<lifecycle/>')
      expect(Dor::WorkflowService.get_lifecycle('dor', 'druid:abc', 'inprocess')).to be_nil
    end
  end

  describe '#get_objects_for_workstep' do
    before :each do
      @repository = 'dor'
      @workflow = 'googleScannedBookWF'
      @completed = 'google-download'
      @waiting = 'process-content'
    end

    context 'a query with one step completed and one waiting' do
      it 'creates the URI string with only the one completed step' do
        expect(@mock_resource).to receive(:[]).with("workflow_queue?waiting=#{@repository}:#{@workflow}:#{@waiting}&completed=#{@repository}:#{@workflow}:#{@completed}&lane-id=default")
        expect(@mock_resource).to receive(:get).and_return(%{<objects count="1"><object id="druid:ab123de4567"/><object id="druid:ab123de9012"/></objects>})
        expect(Dor::WorkflowService.get_objects_for_workstep(@completed, @waiting, 'default', :default_repository => @repository, :default_workflow => @workflow)).to eq(['druid:ab123de4567', 'druid:ab123de9012'])
      end
    end

    context 'a query with TWO steps completed and one waiting' do
      it 'creates the URI string with the two completed steps correctly' do
        second_completed='google-convert'
        expect(@mock_resource).to receive(:[]).with("workflow_queue?waiting=#{@repository}:#{@workflow}:#{@waiting}&completed=#{@repository}:#{@workflow}:#{@completed}&completed=#{@repository}:#{@workflow}:#{second_completed}&lane-id=default")
        expect(@mock_resource).to receive(:get).and_return(%{<objects count="1"><object id="druid:ab123de4567"/><object id="druid:ab123de9012"/></objects>})
        expect(Dor::WorkflowService.get_objects_for_workstep([@completed, second_completed], @waiting, 'default', :default_repository => @repository, :default_workflow => @workflow)).to eq(['druid:ab123de4567', 'druid:ab123de9012'])
      end
    end

    context 'a query using qualified workflow names for completed and waiting' do
      it 'creates the URI string with the two completed steps across repositories correctly' do
        qualified_waiting = "#{@repository}:#{@workflow}:#{@waiting}"
        qualified_completed = "#{@repository}:#{@workflow}:#{@completed}"
        repo2 = 'sdr'
        workflow2 = 'sdrIngestWF'
        completed2='complete-deposit'
        completed3='ingest-transfer'
        qualified_completed2 = "#{repo2}:#{workflow2}:#{completed2}"
        qualified_completed3 = "#{repo2}:#{workflow2}:#{completed3}"
        expect(@mock_resource).to receive(:[]).with("workflow_queue?waiting=#{qualified_waiting}&completed=#{qualified_completed}&completed=#{qualified_completed2}&completed=#{qualified_completed3}&lane-id=default")
        expect(@mock_resource).to receive(:get).and_return(%{<objects count="2"><object id="druid:ab123de4567"/><object id="druid:ab123de9012"/></objects>})
        expect(Dor::WorkflowService.get_objects_for_workstep([qualified_completed, qualified_completed2, qualified_completed3], qualified_waiting)).to eq(['druid:ab123de4567', 'druid:ab123de9012'])
      end

      it 'same but with lane_id' do
        qualified_waiting = "#{@repository}:#{@workflow}:#{@waiting}"
        qualified_completed = "#{@repository}:#{@workflow}:#{@completed}"
        repo2 = 'sdr'
        workflow2 = 'sdrIngestWF'
        completed2='complete-deposit'
        completed3='ingest-transfer'
        qualified_completed2 = "#{repo2}:#{workflow2}:#{completed2}"
        qualified_completed3 = "#{repo2}:#{workflow2}:#{completed3}"
        expect(@mock_resource).to receive(:[]).with("workflow_queue?waiting=#{qualified_waiting}&completed=#{qualified_completed}&completed=#{qualified_completed2}&completed=#{qualified_completed3}&lane-id=lane1")
        expect(@mock_resource).to receive(:get).and_return(%{<objects count="2"><object id="druid:ab123de4567"/><object id="druid:ab123de9012"/></objects>})
        expect(Dor::WorkflowService.get_objects_for_workstep([qualified_completed, qualified_completed2, qualified_completed3], qualified_waiting, 'lane1')).to eq([ 'druid:ab123de4567', 'druid:ab123de9012'])
      end

      it 'creates the URI string with only one completed step passed in as a String' do
        qualified_waiting = "#{@repository}:#{@workflow}:#{@waiting}"
        qualified_completed = "#{@repository}:#{@workflow}:#{@completed}"

        expect(@mock_resource).to receive(:[]).with("workflow_queue?waiting=#{qualified_waiting}&completed=#{qualified_completed}&lane-id=default")
        expect(@mock_resource).to receive(:get).and_return(%{<objects count="1"><object id="druid:ab123de4567"/></objects>})
        expect(Dor::WorkflowService.get_objects_for_workstep(qualified_completed, qualified_waiting)).to eq(['druid:ab123de4567'])
      end

      it 'creates the URI string without any completed steps, only waiting' do
        qualified_waiting = "#{@repository}:#{@workflow}:#{@waiting}"

        expect(@mock_resource).to receive(:[]).with("workflow_queue?waiting=#{qualified_waiting}&lane-id=default")
        expect(@mock_resource).to receive(:get).and_return(%{<objects count="1"><object id="druid:ab123de4567"/></objects>})
        expect(Dor::WorkflowService.get_objects_for_workstep(nil, qualified_waiting)).to eq(['druid:ab123de4567'])
      end

      it 'same but with lane_id' do
        qualified_waiting = "#{@repository}:#{@workflow}:#{@waiting}"

        expect(@mock_resource).to receive(:[]).with("workflow_queue?waiting=#{qualified_waiting}&lane-id=lane1")
        expect(@mock_resource).to receive(:get).and_return(%{<objects count="1"><object id="druid:ab123de4567"/></objects>})
        expect(Dor::WorkflowService.get_objects_for_workstep(nil, qualified_waiting, 'lane1')).to eq([ 'druid:ab123de4567' ])
      end
    end
  end

  context 'get empty workflow queue' do
    it 'returns an empty list if it encounters an empty workflow queue' do
      repository = 'dor'
      workflow = 'googleScannedBookWF'
      completed = 'google-download'
      waiting = 'process-content'
      expect(@mock_resource).to receive(:[]).with("workflow_queue?waiting=#{repository}:#{workflow}:#{waiting}&completed=#{repository}:#{workflow}:#{completed}&lane-id=default")
      expect(@mock_resource).to receive(:get).and_return(%{<objects count="0"/>})
      expect(Dor::WorkflowService.get_objects_for_workstep(completed, waiting, 'default', :default_repository => repository, :default_workflow => workflow)).to eq([])
    end
  end

  describe '#delete_workflow' do
    it 'sends a delete request to the workflow service' do
      expect(@mock_resource).to receive(:[]).with("#{@repo}/objects/#{@druid}/workflows/accessionWF")
      expect(@mock_resource).to receive(:delete)
      Dor::WorkflowService.delete_workflow(@repo, @druid, 'accessionWF')
    end
  end
  describe 'get_milestones' do
    it 'should include the version in with the milestones' do
      xml='<?xml version="1.0" encoding="UTF-8"?><lifecycle objectId="druid:gv054hp4128"><milestone date="2012-01-26T21:06:54-0800" version="2">published</milestone></lifecycle>'
      xml=Nokogiri::XML(xml)
      allow(Dor::WorkflowService).to receive(:query_lifecycle).and_return(xml)
      milestones=Dor::WorkflowService.get_milestones(@repo, @druid)
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
      expect(Dor::WorkflowService.get_active_workflows('dor', 'druid:mw971zk1113')).to eq(['accessionWF'])
    end
  end

  describe '#close_version' do
    it 'calls the versionClose endpoint with druid' do
      expect(@mock_resource).to receive(:[]).with('dor/objects/druid:123/versionClose').and_return(@mock_resource)
      expect(@mock_resource).to receive(:post).with('').and_return('')
      Dor::WorkflowService.close_version(@repo, @druid)
    end

    it 'optionally prevents creation of accessionWF' do
      expect(@mock_resource).to receive(:[]).with('dor/objects/druid:123/versionClose?create-accession=false').and_return(@mock_resource)
      expect(@mock_resource).to receive(:post).with('').and_return('')
      Dor::WorkflowService.close_version(@repo, @druid, false)
    end
  end

  describe '.get_stale_queued_workflows' do
    it 'returns an Array of Hashes containing each workflow step' do
      xml = <<-XML
        <workflows>
            <workflow laneId="lane1" note="annotation" lifecycle="in-process" errorText="stacktrace" errorMessage="NullPointerException" elapsed="1.173" repository="dor" attempts="0" datetime="2008-11-15T13:30:00-0800" status="waiting" process="content-metadata" name="accessionWF" druid="dr:123"/>
            <workflow laneId="lane2" note="annotation" lifecycle="in-process" errorText="stacktrace" errorMessage="NullPointerException" elapsed="1.173" repository="dor" attempts="0" datetime="2008-11-15T13:30:00-0800" status="waiting" process="jp2-create" name="assemblyWF" druid="dr:456"/>
        </workflows>
      XML
      expect(@mock_resource).to receive(:[]).with('workflow_queue/all_queued?repository=dor&hours-ago=24&limit=100')
      expect(@mock_resource).to receive(:get).and_return(xml)

      ah = Dor::WorkflowService.get_stale_queued_workflows 'dor', :hours_ago => 24, :limit => 100
      expected = [ { :workflow => 'accessionWF', :step => 'content-metadata', :druid => 'dr:123', :lane_id => 'lane1'},
                   { :workflow => 'assemblyWF', :step => 'jp2-create', :druid => 'dr:456', :lane_id => 'lane2'} ]
      expect(ah).to eql(expected)
    end
  end

  describe '.count_stale_queued_workflows' do
    it 'returns the number of queued workflow steps' do
      expect(@mock_resource).to receive(:[]).with('workflow_queue/all_queued?repository=dor&hours-ago=48&count-only=true')
      expect(@mock_resource).to receive(:get).and_return(%{<objects count="10"/>})

      expect(Dor::WorkflowService.count_stale_queued_workflows('dor', :hours_ago => 48)).to eq(10)
    end
  end

  describe '.get_lane_ids' do
    it 'returns the lane ids for a given workflow step' do
      xml = <<-XML
      <lanes>
        <lane id="lane1"/>
        <lane id="lane2"/>
      </lanes>
      XML

      expect(@mock_resource).to receive(:[]).with('workflow_queue/lane_ids?step=dor:accessionWF:shelve')
      expect(@mock_resource).to receive(:get).and_return(xml)

      expect(Dor::WorkflowService.get_lane_ids('dor', 'accessionWF', 'shelve')).to eq(%w(lane1 lane2))
    end
  end
end
