lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Bundler.require(:default, :development)

RSpec.configure do |conf|
  
end

Rails = Object.new unless defined? Rails
