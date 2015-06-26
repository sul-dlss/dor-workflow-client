[![Build Status](https://travis-ci.org/sul-dlss/dor-workflow-service.svg?branch=master)](https://travis-ci.org/sul-dlss/dor-workflow-service)
[![Dependency Status](https://gemnasium.com/sul-dlss/dor-workflow-service.svg)](https://gemnasium.com/sul-dlss/dor-workflow-service)

# dor-workflow-service gem

Provides Ruby convenience methods to work with the DOR Workflow REST Service. The REST API is defined here:
https://consul.stanford.edu/display/DOR/DOR+services#DORservices-initializeworkflow

## Usage

To initialize usage of the service, you need to call `Dor::WorkflowService.configure`, like in a bootup or startup method,
e.g.:

```ruby
Dor::WorkflowService.configure('https://test-server.edu/workflow/')
```

If you plan to archive workflows, then you need to set the URL to the Dor REST service:

```ruby
Dor::WorkflowService.configure('https://test-server.edu/workflow/', :dor_services_url => 'https://sul-lyberservices-dev.stanford.edu/dor')
```

There's no need to call `Dor::WorkflowService.configure` if using the `dor-services` gem and using the `Dor::Config`
 object.  The latest versions of `dor-services` will configure the workflow service for you.
