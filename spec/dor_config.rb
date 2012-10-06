require 'confstruct/configuration'

# Bare minimum Confstruct object that allows the service to run.
# Follows how the dor-services gem is configured
module Dor

  class TinyConf < Confstruct::Configuration
    def make_rest_client(url)
      RestClient::Resource.new(url, {})
    end
  end
  
  Config = TinyConf.new
end

Dor::Config.configure do

  workflow do
    url 'http://example.edu/workflow/'
  end
  
end
