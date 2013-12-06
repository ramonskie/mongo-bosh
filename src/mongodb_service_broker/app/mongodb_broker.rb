require 'sinatra/base'
require 'sinatra/async'
require 'json'

class MongodbBroker < Sinatra::Base
  PROVISION_CHANNEL = "mongodb.provision".freeze
  register Sinatra::Async

  use Rack::Auth::Basic do |username, password|
    username == settings.config[:login] && password == settings.config[:password]
  end
  enable :logging


  def self.configure(config, message_bus)
    set :config, config
    set :message_bus, message_bus
  end

  def message_bus
    settings.message_bus
  end

  error do
    puts env['sinatra.error'].message, env['sinatra.error'].backtrace
  end

  get '/v2/catalog' do
    content_type :json
    status 200
    body JSON.dump(services: [ mongodb_service ])
  end

  aput '/v2/service_instances/:id' do |id|
    req = {
      id: id,
      service_id: params[:service_id],
      plan_id: params[:plan_id],
      organization_guid: params[:organization_guid],
      space_guid: params[:space_guid]
    }
    message_bus.request(PROVISION_CHANNEL, command: "provision", data: req) do |resp|
      data = resp["data"]
      content_type :json
      if resp["error"]
        case data["type"]
        when "database_already_exists" then status 409
        else status 500
        end
        body data["message"].to_json
      else
        status 201
        body JSON.dump({})
      end
    end
  end

  aput '/v2/service_instances/:instance_id/service_bindings/:id' do |instance_id, id|
    req = {
      instance_id: instance_id,
      id: id,
      service_id: params[:service_id],
      plan_id: params[:plan_id],
    }
    message_bus.request(PROVISION_CHANNEL, command: "bind", data: req) do |resp|
      content_type :json
      data = resp["data"]
      if resp["error"]
        case data["type"]
        when "already_binded" then status 409
        when "no_database_found" then status 404
        else status 500
        end
        body data["message"].to_json
      else
        status 201
        body JSON.dump(data)
      end
    end
  end

  adelete '/v2/service_instances/:instance_id/service_bindings/:id' do |instance_id, id|
    req = {
      instance_id: instance_id,
      id: id,
      service_id: params[:service_id],
      plan_id: params[:plan_id],
    }
    message_bus.request(PROVISION_CHANNEL, command: "unbind", data: req) do |resp|
      content_type :json
      data = resp["data"]
      if resp["error"]
        case data["type"]
        when "not_binded" then status 410
        when "no_database_found" then status 410
        else status 500
        end
        body "{}"
      else
        status 200
        body "{}"
      end
    end
  end

  adelete '/v2/service_instances/:id' do |id|
    req = {
      id: id,
      service_id: params[:service_id],
      plan_id: params[:plan_id],
    }
    message_bus.request(PROVISION_CHANNEL, command: "unprovision", data: req) do |resp|
      data = resp["data"]
      content_type :json

      if resp["error"]
        case data["type"]
        when "no_database_found" then status 410
        else status 500
        end
        body "{}"
      else
        status 200
        body "{}"
      end
    end
  end

  def mongodb_service
    {
      id: "1",
      name: 'mongodb',
      description: 'Clustered MongoDB service',
      bindable: true,
      plans: [{
                id: "1",
                name: "full",
                description: "Access to whole database"
              }]
    }
  end
end

