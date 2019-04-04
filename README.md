[![Build Status](https://travis-ci.org/sul-dlss/dor-workflow-service.svg?branch=master)](https://travis-ci.org/sul-dlss/dor-workflow-service)

# dor-workflow-service gem

A Ruby client to work with the DOR Workflow REST Service. The REST API is defined here:
https://consul.stanford.edu/display/DOR/DOR+services#DORservices-initializeworkflow

## Usage

As of version `3.x`, you should initialize a `Dor::WorkflowService` object in your application configuration, i.e. in a bootup or startup method like:

```ruby
wfs = Dor::WorkflowService.new(url: 'https://test-server.edu/workflow/')
```

Consumers of recent versions of the [dor-services](https://github.com/sul-dlss/dor-services) gem can access the configured `Dor::WorkflowService` object via `Dor::Config`.

## Underlying Clients

This gem currently uses the [Faraday](https://github.com/lostisland/faraday) HTTP client to access the back-end service.  The clients be accessed directly from your `Dor::WorkflowService` object:

```ruby
wfs.workflow_resource # the Faraday object
```

Or for advanced configurations, ONE of them (not both) can be passed to the constructor instead of the raw URL string:

```ruby
conn = Faraday.new(:url => 'http://sushi.com') do |faraday|
  faraday.request  :url_encoded             # form-encode POST params
  faraday.response :logger                  # log requests to STDOUT
  faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
end
wfs = Dor::WorkflowService.new(connection: conn)
```
