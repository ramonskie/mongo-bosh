require 'rspec/http'
ENV["RACK_ENV"] = "test"

require File.join(File.dirname(File.dirname(__FILE__)), 'app/mongodb_broker.rb')
Dir["#{File.dirname(__FILE__)}/support/*.rb"].each {|file| require file }


RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  config.order = 'random'

end
