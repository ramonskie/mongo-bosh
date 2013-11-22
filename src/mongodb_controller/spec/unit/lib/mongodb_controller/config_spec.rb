require 'spec_helper'

describe VCAP::MongodbController::Config do
  let(:valid_config) do
    {
      "message_bus_uris" => ["nats://1:2@3"],
      "pid_filename" => "/tmp/pid_file",
      "master_node" => true,
      "node_config_file" => "etc/node_config.yml",
      "mongo_key_file" => "/tmp/mongo_key_file",
      "mongod_config_file" => "etc/mongo.conf",
      "mongod_binary" => "/usr/bin/mongod",
      "mongod_port" => 22017,
      "mongod_data_dir" => "/tmp/mongo_data_dir",
      "provision_config" => "/tmp/provision.yml"
    }
  end
  before { expect(YAML).to receive(:load_file).with("file/path").and_return(valid_config) }
  subject { described_class.from_file("file/path") }

  context "#master_node?" do
    it { should be_master_node}
  end
end
