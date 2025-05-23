# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'dor/workflow/client/version'

Gem::Specification.new do |gem|
  gem.name          = 'dor-workflow-client'
  gem.version       = Dor::Workflow::Client::VERSION
  gem.authors       = ['Willy Mene', 'Darren Hardy']
  gem.email         = ['wmene@stanford.edu']
  gem.description   = 'Enables Ruby manipulation of the DOR Workflow Service via its REST API'
  gem.summary       = 'Provides convenience methods to work with the DOR Workflow Service'
  gem.homepage      = 'https://consul.stanford.edu/display/DOR/DOR+services#DORservices-initializeworkflow'
  gem.licenses      = ['Apache-2.0']
  gem.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  gem.require_paths = ['lib']
  gem.required_ruby_version = '>= 3.0'

  gem.add_dependency 'activesupport', '>= 7.0.0'
  gem.add_dependency 'deprecation', '>= 0.99.0'
  gem.add_dependency 'faraday', '~> 2.0'
  gem.add_dependency 'faraday-retry', '~> 2.0'

  gem.add_dependency 'nokogiri', '~> 1.6'
  gem.add_dependency 'zeitwerk', '~> 2.1'

  gem.metadata['rubygems_mfa_required'] = 'true'
end
