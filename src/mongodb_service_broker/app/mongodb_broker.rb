require 'sinatra/base'
require 'sinatra/async'
require 'json'

class MongodbBroker < Sinatra::Base
  ADVERTIZE_CHANNEL = "mongodb.advertise".freeze

  use Rack::Auth::Basic do |username, password|
    username == settings.config[:username] && password == settings.config[:password]
  end

  register Sinatra::Async

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
    message_bus.request(ADVERTIZE_CHANNEL, command: "provision", data: req) do |resp|
      content_type :json
      if resp["error"]
        case resp["type"]
        when "database_already_exists" then status 409
        else status 500
        end
        body resp["message"].to_json
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
    message_bus.request(ADVERTIZE_CHANNEL, command: "bind", data: req) do |resp|
      content_type :json
      if resp["error"]
        case resp["type"]
        when "already_binded" then status 409
        when "no_database_found" then status 404
        else status 500
        end
        body resp["message"].to_json
      else
        status 201
        body JSON.dump(resp["data"])
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
    message_bus.request(ADVERTIZE_CHANNEL, command: "unbind", data: req) do |resp|
      content_type :json
      if resp["error"]
        case resp["type"]
        when "not_binded" then status 404
        when "no_database_found" then status 404
        else status 500
        end
        body resp["message"].to_json
      else
        status 200
        body ""
      end
    end
  end

  adelete '/v2/service_instances/:id' do |id|
    req = {
      id: id,
      service_id: params[:service_id],
      plan_id: params[:plan_id],
    }
    message_bus.request(ADVERTIZE_CHANNEL, command: "unprovision", data: req) do |resp|
      content_type :json
      if resp["error"]
        case resp["type"]
        when "no_database_found" then status 404
        else status 500
        end
        body resp["message"].to_json
      else
        status 200
        body ""
      end
    end
  end

  def mongodb_service
    {
      id: 1,
      name: 'MongoDB Cluster',
      description: 'Clustered MongoDB service',
      plans: [{
                id: 1,
                name: "full",
                description: "Access to whole database"
              }]
    }
  end
end
