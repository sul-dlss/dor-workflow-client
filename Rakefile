require "bundler/setup"

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) do |spec|
#  spec.libs << 'lib' << 'spec'
  spec.pattern = 'spec/**/*_spec.rb', 'test/**/*.rb'
end

require 'yard'
YARD::Rake::YardocTask.new #do |t|
#  t.files   = ['lib/**/*.rb']   # optional
#end

# To release the gem to the DLSS gemserver, run 'rake dlss_release'
require 'dlss/rake/dlss_release'
Dlss::Release.new
