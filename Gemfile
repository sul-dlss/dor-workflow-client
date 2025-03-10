# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in dor-workflow-client.gemspec
gemspec

gem 'activesupport', ENV['RAILS_VERSION'] if ENV['RAILS_VERSION']

group :development, :test do
  gem 'byebug'
  gem 'rspec_junit_formatter' # For CircleCI
end

group :development do
  gem 'rake'
  gem 'rspec', '~> 3.3'
  gem 'rubocop', '~> 1.24'
  gem 'rubocop-rake'
  gem 'rubocop-rspec'
  gem 'simplecov'
  gem 'webmock'
  gem 'yard'
end
