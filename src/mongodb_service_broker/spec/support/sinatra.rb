ENV["RACK_ENV"] = "test"

require 'sinatra'
require 'rspec/http'
require 'eventmachine'
require 'steno'

require File.expand_path '../../../app/mongodb_broker.rb', __FILE__
require "sinatra/async/test"

module RSpecMixin
  include Sinatra::Async::Test::Methods
  def app() described_class.new end
end

# For RSpec 2.x
RSpec.configure { |c| c.include RSpecMixin }
