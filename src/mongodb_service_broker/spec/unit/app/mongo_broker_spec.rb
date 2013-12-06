require 'spec_helper'

describe MongodbBroker do
  subject { last_response }
  let(:config) { {login: "user", password: "password"} }
  let(:message_bus) { double(:message_bus) }
  before { described_class.configure(config, message_bus) }

  context "catalog" do
    context "authorized" do
      before { authorize "user", "password" }
      before { get '/v2/catalog' }

      it { should be_http_ok }
      it do
        expect(subject.body).to be_json_eql <<JSON
{
    "services": [{
        "id": "1",
        "name": "MongoDB Cluster",
        "description": "Clustered MongoDB service",
        "bindable": true,
        "plans": [{
            "id": "1",
            "name": "full",
            "description": "Access to whole database"
        }]
    }]
}
JSON
      end
    end

    context "unauthorized" do
      before { get '/v2/catalog' }

      it { should be_http_unauthorized }
    end
  end

  context "provision" do
    context "authorized" do
      before { authorize "user", "password" }
      let(:data) { {id: 'abc', service_id: '1', plan_id: '1',
          organization_guid: '123', space_guid: '456'}}

      context "success" do
        before do
          expect(message_bus).to receive(:request).with('mongodb.provision', command: "provision",
                                                        data: data).
            and_yield("error" => false, "data" => {"database" => "d1"})
          put '/v2/service_instances/abc', { service_id: 1, plan_id: 1,
            organization_guid: 123, space_guid: 456}
          async_continue
        end

        it { should be_http_created }
        it { expect(subject.body).to eq '{}' }
      end

      context "error" do
        before do
          expect(message_bus).to receive(:request).with('mongodb.provision', command: "provision",
                                                        data: data).
            and_yield("error" => true, "message" => "Exists", "type" => "database_already_exists")
          put '/v2/service_instances/abc', { service_id: 1, plan_id: 1,
            organization_guid: 123, space_guid: 456}
          async_continue
        end

        it { should be_http_conflict }
      end
    end

    context "unauthorized" do
      before { put '/v2/service_instances/abc' }

      it { should be_http_unauthorized }
    end
  end

  context "bind" do
    context "authorized" do
      before { authorize "user", "password" }
      let(:data) { {instance_id: 'abc', id: 'def', service_id: '1', plan_id: '1'} }

      context "success" do
        before do
          credentials = { "uri" => "mongodb://a:b@c/d", "username" => "a",
            "password" => "p", "hosts" => "c", "database" => "d"}
          expect(message_bus).to receive(:request).with('mongodb.provision', command: "bind",
                                                        data: data).
            and_yield("error" => false, "data" => {"credentials" => credentials})
          put '/v2/service_instances/abc/service_bindings/def', { service_id: 1, plan_id: 1}
          async_continue
        end

        it { should be_http_created }
        it do
          expect(subject.body).to be_json_eql <<JSON
{
    "credentials": {
        "uri": "mongodb://a:b@c/d",
        "username": "a",
        "password": "p",
        "hosts": "c",
        "database": "d"
    }
}
JSON
          end
      end

      context "already binded" do
        before do
          expect(message_bus).to receive(:request).with('mongodb.provision', command: "bind",
                                                        data: data).
            and_yield("error" => true, "message" => "Exists", "type" => "already_binded")
          put '/v2/service_instances/abc/service_bindings/def', { service_id: 1, plan_id: 1}
          async_continue
        end

        it { should be_http_conflict }
      end

      context "not found" do
        before do
          expect(message_bus).to receive(:request).with('mongodb.provision', command: "bind",
                                                        data: data).
            and_yield("error" => true, "message" => "Exists", "type" => "no_database_found")
          put '/v2/service_instances/abc/service_bindings/def', { service_id: 1, plan_id: 1}
          async_continue
        end

        it { should be_http_not_found }
      end
    end

    context "unauthorized" do
      before { put '/v2/service_instances/abc/service_instances/def' }

      it { should be_http_unauthorized }
    end
  end

  context "unbind" do
    context "authorized" do
      before { authorize "user", "password" }
      let(:data) { {instance_id: 'abc', id: 'def', service_id: '1', plan_id: '1'} }

      context "success" do
        before do
          expect(message_bus).to receive(:request).with('mongodb.provision', command: "unbind",
                                                        data: data).
            and_yield("error" => false, "data" => {})
          delete '/v2/service_instances/abc/service_bindings/def', { service_id: 1, plan_id: 1}
          async_continue
        end

        it { should be_http_ok }
        it { expect(subject.body).to eq '{}' }
      end

      context "no database" do
        before do
          expect(message_bus).to receive(:request).with('mongodb.provision', command: "unbind",
                                                        data: data).
            and_yield("error" => true, "message" => "No database", "type" => "no_database_found")
          delete '/v2/service_instances/abc/service_bindings/def', { service_id: 1, plan_id: 1}
          async_continue
        end

        it { should be_http_not_found }
      end

      context "not binded" do
        before do
          expect(message_bus).to receive(:request).with('mongodb.provision', command: "unbind",
                                                        data: data).
            and_yield("error" => true, "message" => "Exists", "type" => "not_binded")
          delete '/v2/service_instances/abc/service_bindings/def', { service_id: 1, plan_id: 1}
          async_continue
        end

        it { should be_http_not_found }
      end
    end

    context "unauthorized" do
      before { delete '/v2/service_instances/abc/service_instances/def' }

      it { should be_http_unauthorized }
    end
  end

  context "unprovision" do
    context "authorized" do
      before { authorize "user", "password" }
      let(:data) { {id: 'abc', service_id: '1', plan_id: '1'} }

      context "success" do
        before do
          expect(message_bus).to receive(:request).with('mongodb.provision', command: "unprovision",
                                                        data: data).
            and_yield("error" => false, "data" => {})
          delete '/v2/service_instances/abc', { service_id: 1, plan_id: 1}
          async_continue
        end

        it { should be_http_ok }
        it { expect(subject.body).to eq '{}' }
      end

      context "no database" do
        before do
          expect(message_bus).to receive(:request).with('mongodb.provision', command: "unprovision",
                                                        data: data).
            and_yield("error" => true, "message" => "No database", "type" => "no_database_found")
          delete '/v2/service_instances/abc', { service_id: 1, plan_id: 1}
          async_continue
        end

        it { should be_http_not_found }
      end
    end

    context "unauthorized" do
      before { delete '/v2/service_instances/abc/service_instances/def' }

      it { should be_http_unauthorized }
    end
  end
end
