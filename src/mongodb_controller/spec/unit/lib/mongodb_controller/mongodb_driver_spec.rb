require 'spec_helper'

describe VCAP::MongodbController::MongodbDriver do
  let(:global_config) {{
      pid_filename: '/tmp/mongo.pid',
      node_config_file: '/tmp/config',
      mongod_config_file: '/etc/mongo.conf',
      mongod_binary: '/bin/mongo',
      mongod_port: 27017,
      mongod_data_dir: '/tmp/mongo/data',
      mongo_key_file: '/tmp/keyfile'
    }}
  before { allow(File).to receive(:open).with('/tmp/config', 'w') }
  subject { described_class.new(global_config, ) }
  describe '#update_config' do
    context 'master' do
      it 'should generate config for master' do
        mongo_config = <<END_CONFIG
syslog = false
dbpath=/tmp/mongo/data
keyFile=/tmp/keyfile

directoryperdb=true

replSet=rs0
port=27017

vvvvv=true
noprealloc=true
smallfiles=true
nopreallocj=true
END_CONFIG
        should_save(mongo_config, '/etc/mongo.conf')

        subject.update_config(master: true)
      end
    end

    context 'slave' do
      it 'should generate config for slave' do
        mongo_config = <<END_CONFIG
syslog = false
dbpath=/tmp/mongo/data
keyFile=/tmp/keyfile

directoryperdb=true

replSet=rs1
port=27017

vvvvv=true
noprealloc=true
smallfiles=true
nopreallocj=true
END_CONFIG
        should_save(mongo_config, '/etc/mongo.conf')

        subject.update_config(replication_set: 'rs1')
      end
    end
  end

  describe '#start' do
    it "should start mongo" do
      allow(subject).to receive(:node_config).and_return({})
      expect(EM).to receive(:popen).with(['/bin/mongo', '--config', '/etc/mongo.conf'],
                                         VCAP::MongodbController::MongodProcess,
                                         subject, 27017)

      subject.start
    end

  end

  describe '#started' do
    it 'configures mongo' do
      con = double(:connection)
      expect(EM::Mongo::Connection).to receive(:new).with('127.0.0.1', 27017, 20, reconnect_in: 30).
        and_return(con)
      expect(con).to receive(:callback)
      subject.started

      expect(subject.state).to eq :started
    end

  end
end
