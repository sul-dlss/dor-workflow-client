[![Build Status](https://travis-ci.org/sul-dlss/dor-workflow-service.svg?branch=master)](https://travis-ci.org/sul-dlss/dor-workflow-service)
[![Dependency Status](https://gemnasium.com/sul-dlss/dor-workflow-service.svg)](https://gemnasium.com/sul-dlss/dor-workflow-service)

# dor-workflow-service gem

Provides Ruby convenience methods to work with the DOR Workflow REST Service. The REST API is defined here:
https://consul.stanford.edu/display/DOR/DOR+services#DORservices-initializeworkflow

## Usage

As of version `2.x`, you should initialize a `Dor::WorkflowService` object in your application configuration, i.e. in a bootup or startup method like:

```ruby
wfs = Dor::WorkflowService.new('https://test-server.edu/workflow/')
```

If you plan to archive workflows, then you need to set the URL to the Dor REST service:

```ruby
wfs = Dor::WorkflowService.new('https://test-server.edu/workflow/', :dor_services_url => 'https://sul-lyberservices-dev.stanford.edu/dor')
```

Consumers of recent versions of the [dor-services](https://github.com/sul-dlss/dor-services) gem can access the configured `Dor::WorkflowService` object via `Dor::Config`.

## Underlying Clients

This gem currently uses both [RestClient::Resource](https://github.com/rest-client/rest-client/blob/master/lib/restclient/resource.rb)
and [Faraday](https://github.com/lostisland/faraday) client gems to access the back-end service.  The clients be accessed directly from your `Dor::WorkflowService` object:

```ruby
wfs.resource  # the RestClient::Resource
wfs.http_conn # the Faraday object
```

Or for advanced configurations, ONE of them (not both) can be passed to the constructor instead of the raw URL string:

```ruby
conn = Faraday.new(:url => 'http://sushi.com') do |faraday|
  faraday.request  :url_encoded             # form-encode POST params
  faraday.response :logger                  # log requests to STDOUT
  faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
end
wfs = Dor::WorkflowService.new(conn)
```

The corresponding client will be constructed off the same URL.  If this is insufficient, you can always set a client directly:

```ruby
wfs.resource = RestClient::Resource('http://protected/resource', :user => 'user', :password => 'password', :read_timeout => 10)
```
