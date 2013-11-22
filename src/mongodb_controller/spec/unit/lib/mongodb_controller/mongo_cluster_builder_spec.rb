require 'spec_helper'

describe VCAP::MongodbController::MongoClusterBuilder do
  def create_config(params)
    VCAP::MongodbController::Config.new({
                                          message_bus_uris: ["some_uri"],
                                          pid_filename: "some file",
                                          master_node: params[:master],
                                          node_config_file: "etc/node_config.yml",
                                          mongod_config_file: "etc/mongo.conf"
                                        })
  end
  let(:message_bus) { double(:nats) }
  let(:mongodb_driver) { double(:mongodb_driver) }
  let(:provision_config) { double(:provision_config) }
  subject { described_class.new(config, message_bus, provision_config,mongodb_driver) }

  context "master node" do
    context "startup" do
      let(:config) { create_config(master: true)}
      before{ message_bus.stub(:subscribe).with("mongodb.advertise") }
      before{ message_bus.stub(:subscribe).with("mongodb.provision") }

      it "should run MongoDB with existant config" do
        mongodb_driver.should receive(:update_config)
        mongodb_driver.should receive(:stop)
        mongodb_driver.should receive(:start)
        mongodb_driver.should receive(:run_on_mongo)
        allow(provision_config).to receive(:[]).with(:configured?).and_return(false)
        allow(provision_config).to receive(:update)
      end

      after { subject.run }
    end

    context "slave attaches" do
      context "startup" do
        let(:config) { create_config(master: false)}
        let(:node_config) { double(:node_config) }
        let(:response) { {command: "update_config", data: {replication_set: 'rs1'}} }
        before do
          expect(provision_config).to receive(:merge).and_return(node_config)
          expect(provision_config).to receive(:update)
          message_bus.stub(:request).with("mongodb.advertise", anything).
            and_yield(response)

          expect(mongodb_driver).to receive(:update_config).with({replication_set: 'rs1'})
          expect(mongodb_driver).to receive(:stop)
          expect(mongodb_driver).to receive(:start)
        end

        it "updates config" do
          subject.run
        end
      end
    end
  end
end
