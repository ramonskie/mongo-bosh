require 'spec_helper'

describe VCAP::MongodbController::MongoClusterBuilder do
  def create_config(params)
    VCAP::MongodbController::Config.new({
                                          message_bus_uri: "some_uri",
                                          pid_filename: "some file",
                                          master_node: params[:master],
                                          node_config_file: "etc/node_config.yml",
                                          mongodb_config_file: "etc/mongo.conf"
                                        })
  end
  let(:message_bus) { double(:nats) }
  let(:mongodb_driver) { double(:mongodb_driver) }
  subject { described_class }
  before{ described_class.configure(config, message_bus, mongodb_driver) }

  context "master node" do
    context "startup" do
      let(:config) { create_config(master: true)}
      before{ message_bus.stub(:subscribe).with("mongodb.advertise") }

      it "should run MongoDB with existant config" do
        mongodb_driver.should receive(:start)
      end

      after { described_class.run }
    end

    context "slave attaches" do
      context "startup" do
        let(:config) { create_config(master: false)}
        let(:node_config) { double(:node_config) }
        let(:response) { {command: "update_config", data: {replication_set: 'rs1'}} }
        before do
          message_bus.stub(:request).with("mongodb.advertise", anything).
            and_yield(response)
          mongodb_driver.stub(:node_config).and_return(node_config)

          mongodb_driver.should receive(:apply_config).with({replication_set: 'rs1'})
        end

        it "updates config" do
          described_class.run
        end
      end
    end
  end

  context "slave node" do
    context "configured" do
      it "should send update  to master"
      it "should run MongoDB database"
    end

    context "not configured" do
      it "should request master role from master"
      it "should start MongoDB afrer it"
    end
  end
end
