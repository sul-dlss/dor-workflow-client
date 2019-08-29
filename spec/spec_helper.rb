# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter 'spec'
end

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'byebug'
require 'dor/workflow/client'
require 'webmock/rspec'

# RSpec.configure do |conf|
# end
