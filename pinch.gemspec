lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'pinch'

Gem::Specification.new do |s|
  s.required_ruby_version = '>= 3.0.0'
  s.require_paths << 'lib'

  s.name        = "pinch"
  s.version     = Pinch::VERSION
  s.summary     = "Retrieve a file from inside a zip file, over the network!"
  s.description = "Pinch makes it possible to download a specific file from within a ZIP file over HTTP 1.1."
  s.email       = "peter@c7.se"
  s.homepage    = "http://peterhellberg.github.com/pinch/"
  s.authors     = ["Peter Hellberg", "Edward Patel"]
  s.license     = "MIT-LICENSE"

  s.rdoc_options      = ['--main', 'README.rdoc', '--charset=UTF-8']
  s.extra_rdoc_files  = ['README.rdoc', 'MIT-LICENSE']

  s.test_file         = 'spec/pinch_spec.rb'

  s.files             = Dir.glob("lib/**/*") +
                        %w(MIT-LICENSE README.rdoc Rakefile .gemtest)

  s.add_dependency 'net-http'

  s.add_development_dependency 'minitest'
  s.add_development_dependency 'webmock'
  s.add_development_dependency 'vcr'
end
