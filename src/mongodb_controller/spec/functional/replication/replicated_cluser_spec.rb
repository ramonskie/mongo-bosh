require 'spec_helper'
require 'mongo'

describe 'Replicated two node cluster' do
  let(:config1) { create_node_config(master: true) }
  let(:process1) { create_server_process(config1.path) }
  let(:config2) { create_node_config() }
  let(:process2) { create_server_process(config2.path) }
  let(:mongo_client) { ::Mongo::MongoClient.new('127.0.0.1', config1.port) }
  let(:message_bus) { ::CfMessageBus::MessageBus.new(uri: 'nats://user:password@127.0.0.1:4222',
                                                     logger: Logger.new(STDOUT)) }
  around do |s|
    error = nil
    EM.error_handler do |e|
      error = e
      puts "aa", e, e.backtrace
      EM.stop
    end
    s.call
    raise error if error
  end

  it 'should start' do
    process1.start
    process1.wait_startup(config1.port)
    process2.start
    process1.wait_startup(config2.port)
    wait_timeout('MongoDB replication configured', 20.seconds) do
      repl_set =  mongo_client['local']['system.replset'].find_one
      repl_set && repl_set['members'].length == 2
    end

    EM.run do
      EM.add_timer(60) { EM.stop; raise "Test timed out" }
      check_provisioning('some-id')
    end

  end

  def check_provisioning(id)
    data = {
      id: id,
      service_id: "service1",
      plan_id: "1",
      organization_guid: "org-guid",
      space_guid: "space-guid"
    }
    message_bus.request('mongodb.provision', command: 'provision', data: data) do |r|
      expect(r['error']).to eq(false)
      check_bind('bad-id', 'some_id', false)
      check_bind(id, 'bind_id', true)
    end
  end

  def check_bind(instance_id, id, should_success = true)
    data = {
      instance_id: instance_id,
      id: id,
      service_id: "service1",
      plan_id: "1",
    }
    message_bus.request('mongodb.provision', command: 'bind', data: data) do |r|
      if should_success
        expect(r['error']).to eq(false)
        expect(r['data']).to be_kind_of Hash
        expect(r['data']['credentials']).to be_kind_of Hash
        check_bind_credentials(instance_id, id, r['data']['credentials'])
      else
        expect(r['error']).to eq(true)
      end
    end
  end

  def check_bind_credentials(instance_id, id, credentials)
    uri = credentials["uri"]
    r = %r{^mongodb://(?<user>.+):(?<password>.+)@(?<hosts>[^/]+)/(?<path>.+)$}
    m = r.match uri
    expect(m[:user]).to eq credentials["username"]
    expect(m[:password]).to eq credentials["password"]
    expect(m[:path]).to eq credentials["database"]
    expect(m[:hosts]).to eq ["127.0.0.1:#{config1.port}", "127.0.0.1:#{config2.port}"].join(',')
    ::Mongo::MongoClient.new('127.0.0.1', config1.port).
      db(m[:path]).authenticate(m[:user], m[:password]) #checking auth

    check_unbind(instance_id, "bad" + id, credentials, false)
    check_unbind(instance_id, id, credentials, true)
  end

  def check_unbind(instance_id, id, credentials, should_succeed = true)
    data = {
      instance_id: instance_id,
      id: id,
      service_id: "service1",
      plan_id: "1",
    }
    message_bus.request('mongodb.provision', command: 'unbind', data: data) do |r|
      if should_succeed
        expect(r['error']).to eq(false)
        expect { ::Mongo::MongoClient.new('127.0.0.1', config1.port).
          db(credentials["database"]).
          authenticate(credentials["username"], credentials["password"]) }.
          to raise_exception(Mongo::AuthenticationError)

        check_unprovision("bad_" + instance_id, credentials["database"],false)
        check_unprovision(instance_id, credentials["database"], true)
      else
        expect(r['error']).to eq(true)
      end
    end
  end

  def check_unprovision(id, db_name, should_succeed = true)
    data = {
      id: id,
      service_id: "service1",
      plan_id: "1",
    }
    expect(mongo_client.database_info).to have_key db_name
    message_bus.request('mongodb.provision', command: 'unprovision', data: data) do |r|
      if should_succeed
        expect(r['error']).to eq(false)
        expect(mongo_client.database_info).to_not have_key db_name
        EM.stop
      else
        expect(r['error']).to eq(true)
      end
    end
  end

  after { process1.stop }
  after { config1.unlink }
  after { process2.stop }
  after { config2.unlink }
end
