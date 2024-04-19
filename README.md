[![CircleCI](https://circleci.com/gh/sul-dlss/dor-workflow-client.svg?style=svg)](https://circleci.com/gh/sul-dlss/dor-workflow-client)
[![Test Coverage](https://api.codeclimate.com/v1/badges/ff9d01af29a7a357645c/test_coverage)](https://codeclimate.com/github/sul-dlss/dor-workflow-client/test_coverage)
[![Maintainability](https://api.codeclimate.com/v1/badges/ff9d01af29a7a357645c/maintainability)](https://codeclimate.com/github/sul-dlss/dor-workflow-client/maintainability)

[![Gem Version](https://badge.fury.io/rb/dor-workflow-client.svg)](https://badge.fury.io/rb/dor-workflow-client)

# dor-workflow-client gem

A Ruby client to work with the DOR Workflow REST Service. The REST API is defined here:
https://consul.stanford.edu/display/DOR/DOR+services#DORservices-initializeworkflow

## Usage

Initialize a `Dor::Workflow::Client` object in your application configuration, i.e. in a bootup or startup method like:

```ruby
client = Dor::Workflow::Client.new(url: 'https://test-server.edu/workflow/')
```

Consumers of recent versions of the [dor-services](https://github.com/sul-dlss/dor-services) gem can access the configured `Dor::Workflow::Client` object via `Dor::Config`.

## Console

During development, you can test the gem locally on your laptop, hitting a local instance of workflow-server-rails via the console:

```ruby
bin/console

client = Dor::Workflow::Client.new(url: 'http://localhost:3000')
client.create_workflow_by_name('druid:bc123df4567', 'accessionWF', version: '1', context: { 'requireOCR' => true})

client.workflows('druid:bc123df4567')
 => ["accessionWF"]

client.workflow(pid: 'druid:bc123df4567', workflow_name: 'accessionWF')
=> #<Dor::Workflow::Response::Workflow:0x0000000105c8b440

client.process(pid: 'druid:bc123df4567', workflow_name: 'accessionWF', process: 'start-accession').context
 => {"requireOCR"=>true}

client.all_workflows(pid: 'druid:bc123df4567')
=> #<Dor::Workflow::Response::Workflows:0x00000001055d29a0>.....
```

## API
[Rubydoc](https://www.rubydoc.info/github/sul-dlss/dor-workflow-client/main)

### Workflow Variables

If a workflow or workflows for a particular object require data to be persisted and available between steps, workflow variables can be set.  These are per object/version pair and thus available to any step in any workflow for a given version of an object once set.  Pass in a context variable as a Hash as shown in the example below.  The context will be returned as a hash when fetching workflows data for an object.

### Example usage
Create a workflow
```
client.create_workflow_by_name('druid:bc123df4567', 'etdSubmitWF', version: '1')
```

Create a workflow and send in context
```
client.create_workflow_by_name('druid:bc123df4567', 'etdSubmitWF', version: '1', context: { foo: 'bar'} )
```

Update a workflow step's status
```ruby
client.update_status(druid: 'druid:bc123df4567',
                     workflow: 'etdSubmitWF',
                     process: 'registrar-approval',
                     status: 'completed')
```

Fetch information about a workflow:
```ruby
client.workflow(pid: 'druid:bc123df4567', workflow_name: 'etdSubmitWF')
 => #<Dor::Workflow::Response::Workflow:0x000000010cb28588
```

Fetch information about a workflow step:
```ruby
client.process(pid: 'druid:bc123df4567', workflow_name: 'etdSubmitWF', process: 'registrar-approval')
 => #<Dor::Workflow::Response::Process:0x000000010c505098
```

Fetch version context about a workflow step:
```ruby
client.process(pid: 'druid:bc123df4567', workflow_name: 'etdSubmitWF', process: 'registrar-approval').context
 => {"foo"=>"bar"}
```

Show "milestones" for an object
```ruby
client.milestones(druid: 'druid:gv054hp4128')
#=> [{version: '1', milestone: 'published'}]
```

List workflow templates
```ruby
client.workflow_templates
```

Show a workflow template
```ruby
client.workflow_template('etdSubmitWF')
```

Get the status of an object
```ruby
client.status(druid: 'druid:gv054hp4128', version: '3').display
#=> "v3 Accessioned"
```

## Underlying Clients

This gem currently uses the [Faraday](https://github.com/lostisland/faraday) HTTP client to access the back-end service.  The clients be accessed directly from your `Dor::Workflow::Client` object:

```ruby
wfs.connection # the Faraday object
```

Or for advanced configurations, ONE of them (not both) can be passed to the constructor instead of the raw URL string:

```ruby
conn = Faraday.new(:url => 'http://sushi.com') do |faraday|
  faraday.request  :url_encoded             # form-encode POST params
  faraday.response :logger                  # log requests to STDOUT
  faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
end
wfs = Dor::Workflow::Client.new(connection: conn)
```
