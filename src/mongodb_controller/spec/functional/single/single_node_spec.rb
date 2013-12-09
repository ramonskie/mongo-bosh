require 'spec_helper'

describe "Single node cluster" do
  let(:config1) { create_node_config(master: true) }
  let(:process1) { create_server_process(config1.path) }
  include_examples "functional test"

  it "should start" do
    process1.start
    process1.wait_startup(config1.port)
  end

  after { process1.stop }
  after { config1.unlink }
end
