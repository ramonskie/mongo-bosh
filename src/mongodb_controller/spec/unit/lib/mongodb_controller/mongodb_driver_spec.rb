require 'spec_helper'

describe VCAP::MongodbController::MongodbDriver do
  let(:global_config) {{
      pid_filename: "/tmp/mongo.pid",
      node_config_file: "/tmp/config",
      mongod_config_file: "/etc/mongo.conf",
      mongod_binary: "/bin/mongo",
      mongod_port: 27017,
      mongod_data_dir: '/tmp/mongo/data',
    }}
  before { allow(File).to receive(:open).with("/tmp/config", "w") }
  subject { described_class.new(global_config) }
  describe "#apply_config" do
    context "master" do
      it "should generate config for master" do
        mongo_config = <<END_CONFIG
syslog = false
pidfilepath=/tmp/mongo.pid
dbpath=/tmp/mongo/data

directoryperdb=true

replSet=rs0
port=27017
vvvvv=true
noprealloc=true
smallfiles=true
nopreallocj=true
END_CONFIG
        should_save(mongo_config, "/etc/mongo.conf")
        expect(subject).to receive(:stop)
        expect(subject).to receive(:start)

        subject.apply_config(master: true)
      end
    end

    context "slave" do
      it "should generate config for slave" do
        mongo_config = <<END_CONFIG
syslog = false
pidfilepath=/tmp/mongo.pid
dbpath=/tmp/mongo/data

directoryperdb=true

replSet=rs1
port=27017
vvvvv=true
noprealloc=true
smallfiles=true
nopreallocj=true
END_CONFIG
        should_save(mongo_config, "/etc/mongo.conf")
        expect(subject).to receive(:stop)
        expect(subject).to receive(:start)

        subject.apply_config(replication_set: 'rs1')
      end
    end
  end

  describe "#start" do
    it "shouldn't start slave without config" do
      expect(global_config).to receive(:master_node?).and_return(false)
      allow(subject).to receive(:node_config).and_return({})
      expect(subject).not_to receive(:start_mongo)

      subject.start
    end

    it "should start master without config" do
      expect(global_config).to receive(:master_node?).and_return(true)
      allow(subject).to receive(:node_config).and_return({}, {master: true, configured?: true})
      expect(subject).to receive(:apply_config).with(master: true, configured?: true)
      expect(subject).to receive(:start_mongo)

      subject.start
    end
  end

  describe "#start_mongo" do
    it "starts mongo process" do
      expect(EM).to receive(:popen).with(['/bin/mongo', '--config', '/etc/mongo.conf'],
                                         VCAP::MongodbController::MongodbDriver::MongodProcess,
                                         subject, 27017)
      allow(subject).to receive(:node_config).and_return({some: :config, configured?: true})

      subject.start

      expect(subject.state).to eq(:starting)
    end
  end

  describe "#started" do
    it "configures mongo" do
      con = double(:connection)
      expect(EM::Mongo::Connection).to receive(:new).with("127.0.0.1", 27017, 3, reconnect_in: 3).
        and_return(con)
      expect(con).to receive(:callback)
      expect(subject).to receive(:run_on_mongo)
      subject.started

      expect(subject.state).to eq :started
    end

    context "master" do
      it "should initialize replication" do
      end
    end
  end
end
