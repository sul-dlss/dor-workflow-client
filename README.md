[![Build Status](https://travis-ci.org/sul-dlss/dor-workflow-client.svg?branch=master)](https://travis-ci.org/sul-dlss/dor-workflow-client)
[![Test Coverage](https://api.codeclimate.com/v1/badges/fba77ff479c468f8510f/test_coverage)](https://codeclimate.com/github/sul-dlss/dor-services-client/test_coverage)
[![Maintainability](https://api.codeclimate.com/v1/badges/fba77ff479c468f8510f/maintainability)](https://codeclimate.com/github/sul-dlss/dor-services-client/maintainability)
[![Gem Version](https://badge.fury.io/rb/dor-workflow-client.svg)](https://badge.fury.io/rb/dor-workflow-client)

# dor-workflow-client gem

A Ruby client to work with the DOR Workflow REST Service. The REST API is defined here:
https://consul.stanford.edu/display/DOR/DOR+services#DORservices-initializeworkflow

## Usage

You should initialize a `Dor::Workflow::Client` object in your application configuration, i.e. in a bootup or startup method like:

```ruby
client = Dor::Workflow::Client.new(url: 'https://test-server.edu/workflow/')
```

Consumers of recent versions of the [dor-services](https://github.com/sul-dlss/dor-services) gem can access the configured `Dor::Workflow::Client` object via `Dor::Config`.

## API
[Rubydoc](https://www.rubydoc.info/github/sul-dlss/dor-workflow-client/master)

### Example usage
Create a workflow
```
client.create_workflow_by_name('druid:bc123df4567', 'etdSubmitWF', version: '1')
```

Update a workflow step's status
```ruby
client.update_status(druid: 'druid:bc123df4567',
                     workflow: 'etdSubmitWF',
                     process: 'registrar-approval',
                     status: 'completed')
```

Show "milestones" for an object
```ruby
client.milestones('dor', 'druid:gv054hp4128')
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
