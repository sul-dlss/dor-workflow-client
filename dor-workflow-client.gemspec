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

  gem.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  gem.test_files    = gem.files.grep(%r{^(spec)/})
  gem.require_paths = ['lib']

  gem.add_dependency 'activesupport', '>= 3.2.1', '< 7'
  gem.add_dependency 'deprecation', '>= 0.99.0'
  gem.add_dependency 'faraday', '>= 0.9.2', '< 2.0'
  gem.add_dependency 'faraday_middleware'
  gem.add_dependency 'nokogiri', '~> 1.6'
  gem.add_dependency 'zeitwerk', '~> 2.1'

  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rspec', '~> 3.3'
  gem.add_development_dependency 'rubocop', '~> 0.63.1'
  gem.add_development_dependency 'simplecov', '~> 0.17.0' # CodeClimate cannot use SimpleCov >= 0.18.0 for generating test coverage
  gem.add_development_dependency 'webmock'
  gem.add_development_dependency 'yard'
end
