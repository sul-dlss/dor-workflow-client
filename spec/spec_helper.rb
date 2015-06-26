lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'dor-workflow-service'
require 'equivalent-xml'
require 'equivalent-xml/rspec_matchers'

Bundler.require(:default, :development)

# RSpec.configure do |conf|
# end

Rails = Object.new unless defined? Rails
