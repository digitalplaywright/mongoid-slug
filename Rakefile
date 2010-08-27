require 'rspec/core/rake_task'
require 'jeweler'

task :default => :spec

desc "Run all specs in spec directory"
RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = "spec/**/*_spec.rb"
end
  
Jeweler::Tasks.new do |gemspec|
  gemspec.name = "mongoid_slug"
  gemspec.summary = "Generates a URL slug in a Mongoid model"
  gemspec.description = "Mongoid Slug generates a URL slug/permalink based on fields in a Mongoid model."
  gemspec.add_runtime_dependency("mongoid", [">= 2.0.0.beta.15"])
  gemspec.files = Dir.glob("lib/**/*") + %w(LICENSE README.rdoc)
  gemspec.require_path = 'lib'
  gemspec.email = "iamnader@gmail.com"
  gemspec.homepage = "http://github.com/papercavalier/mongoid-slug"
  gemspec.authors = ["Hakan Ensari", "Gerhard Lazu"]
end
Jeweler::GemcutterTasks.new
