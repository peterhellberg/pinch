require 'rake/testtask'
require 'bundler/gem_tasks'

task :default => :test

Rake::TestTask.new(:test) do |t|
  t.test_files = FileList['spec/*_spec.rb']
  t.ruby_opts = ['-rubygems'] if defined? Gem
  t.ruby_opts << '-w -I.'
end
