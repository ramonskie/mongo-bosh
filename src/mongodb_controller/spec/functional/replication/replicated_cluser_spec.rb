require 'spec_helper'
require 'mongo'

describe "Replicated two node cluster" do
  let(:config1) { create_node_config(master: true) }
  let(:process1) { create_server_process(config1.path) }
  let(:config2) { create_node_config() }
  let(:process2) { create_server_process(config2.path) }
  let(:mongo_client) { ::Mongo::MongoClient.new('127.0.0.1', config1.port) }

  it "should start" do
    process1.start
    process1.wait_startup(config1.port)
    process2.start
    process1.wait_startup(config2.port)
    wait_timeout("MongoDB replication configured", 20.seconds) do
      repl_set =  mongo_client['local']['system.replset'].find_one
      repl_set && repl_set["members"].length == 2
    end
  end

  after { process1.stop }
  after { config1.unlink }
  after { process2.stop }
  after { config2.unlink }
end
