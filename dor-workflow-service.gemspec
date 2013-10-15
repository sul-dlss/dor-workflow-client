# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'dor/workflow_version'

Gem::Specification.new do |gem|
  gem.name          = "dor-workflow-service"
  gem.version       = Dor::Workflow::Service::VERSION
  gem.authors       = ["Willy Mene"]
  gem.email         = ["wmene@stanford.edu"]
  gem.description   = "Enables Ruby manipulation of the DOR Workflow Service via its REST API"
  gem.summary       = "Provides convenience methods to work with the DOR Workflow Service"
  gem.homepage      = "https://consul.stanford.edu/display/DOR/DOR+services#DORservices-initializeworkflow"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency "activesupport"
  gem.add_dependency "nokogiri"
  gem.add_dependency "rest-client"
  gem.add_dependency "confstruct"

  gem.add_development_dependency "rake"
  gem.add_development_dependency "rspec"
  gem.add_development_dependency "debugger"
  gem.add_development_dependency "yard"
  gem.add_development_dependency "redcarpet"
  gem.add_development_dependency "equivalent-xml"
end
