require "rubygems"
require "bundler/setup"

require "database_cleaner"
require "mongoid"
require "stringex"
require "rspec"

require 'yaml' 

YAML::ENGINE.yamler = 'syck' 

Mongoid.configure do |config|
  name = "mongoid_slug_test"
  config.master = Mongo::Connection.new.db(name)
end

require File.expand_path("../../lib/mongoid/slug", __FILE__)

Dir["#{File.dirname(__FILE__)}/models/*.rb"].each { |f| require f }

RSpec.configure do |c|
  c.before(:all)  { DatabaseCleaner.strategy = :truncation }
  c.before(:each) { DatabaseCleaner.clean }
end
