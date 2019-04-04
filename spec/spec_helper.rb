# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'simplecov'
SimpleCov.start do
  add_filter 'spec'
end

require 'byebug'
require 'dor/workflow/client'
require 'equivalent-xml'
require 'equivalent-xml/rspec_matchers'

# RSpec.configure do |conf|
# end
