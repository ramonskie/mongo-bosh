require 'eventmachine'
require "sinatra/async/test"

require File.expand_path '../../../app/mongodb_broker.rb', __FILE__

module RSpecMixin
  include Sinatra::Async::Test::Methods
  def app() described_class.new end
end

# For RSpec 2.x
RSpec.configure { |c| c.include RSpecMixin }
