require_relative 'mongodb_driver'
require_relative 'updatable_config'
require 'digest/md5'

module VCAP::MongodbController
  class MongoProvisioner
    PROVISION_CHANNEL = "mongodb.provision".freeze

    attr_reader :config, :message_bus, :driver, :provision_config, :nodes

    def initialize(config, message_bus, node_config, driver)
      @config = config
      @message_bus = message_bus
      @driver = driver
      @provision_config = UpdatableConfig.new(config[:provision_config])
      node_config.add_observer(self, :node_config_changed) if config.master_node?
    end

    def logger
      @logger ||= Steno.logger("mc.provisioner")
    end

    def run
      if config.master_node?
        attach_as_master
      end
    end

    def node_config_changed(c)
      @nodes = c[:nodes]
    end

    private
    def attach_as_master
      logger.info "Attaching as master"
      message_bus.subscribe(PROVISION_CHANNEL) do |msg, reply|
        process_provision_message(msg, reply)
      end

      driver.start
    end

    def process_provision_message(msg, reply)
      logger.info "Processing message", msg
      r = MongoCommand.new
      case msg["command"]
      when "provision" then provision(r, msg["data"])
      when "unprovision" then unprovision(r, msg["data"])
      when "bind" then bind(r, msg["data"])
      when "unbind" then unbind(r, msg["data"])
      else
        message_bus.publish(reply, {error: true, message: "Unknown command #{e}"})
      end

      r.callback {|d| message_bus.publish(reply, {error: false, data: d}) }.
        errback do |e|
        logger.warn(e[:message], e)
        message_bus.publish(reply, {error: true, data: e})
      end
    rescue e
      logger.warn(e[:message], e)
      message_bus.publish(reply, {error: true, data: e})
    end

    # Provision database for controller
    # Data is a hash with items:
    # * id is provision instance id
    def provision(r, data)
      id = data["id"]
      provision_config.update do |c|
        d = generate_database_name
        if c[id]
          r.fail(message: "Database already exists", type: :database_already_exists)
        else
          c[id] = { database: d, users: {} }
        end
      end
      r.succeed
    end

    # Bind database (create credentials)
    # Data is a hash with items:
    # * instance_id is provision instance id
    # * id is binding id
    # returns credentials object
    def bind(r, data)
      instance_id = data["instance_id"]
      id = data["id"]
      instance = nil

      config = provision_config.update do |c|
        instance = c[instance_id]
        return r.fail(message: "No database found", type: :no_database_found) unless instance
        user = instance[:users][id]
        return r.fail(message: "Already binded", type: :already_binded) unless user.nil?

        instance[:users][id] = {
          user: generate_user_name,
          password: generate_password
        }
      end

      credentials = build_credentials(instance[:database], config[:user], config[:password])

      driver.connection.db(instance[:database]).collection("system.users").
        safe_insert(user: config[:user],
                    pwd: to_mongo_password(config[:user], config[:password]),
                    roles: %w(readWrite dbAdmin)).
        callback { r.succeed(credentials: credentials) }.
        errback {|e| r.error(e)}
    end

    def unbind(r, data)
      instance_id = data["instance_id"]
      id = data["id"]
      instance = nil
      user = nil

      provision_config.update do |c|
        instance = c[instance_id]
        return r.fail(message: "No database found", type: :no_database_found) unless instance
        user = instance[:users][id]

        return r.fail(message: "Not binded", type: :not_binded) if user.nil?

        instance[:users].delete(id)
      end

      driver.connection.db(instance[:database]).collection("system.users").
        remove(user: user[:user])
      r.succeed({})
    end

    def unprovision(r, data)
      id = data["id"]
      instance = nil

      provision_config.update do |c|
        instance = c[id]
        return r.fail(message: "No database found", type: :no_database_found) unless instance
        c.delete(id)
      end

      driver.connection.db(instance[:database]).command(dropDatabase: 1).
        callback{ r.succeed({}) }.
        errback{|e| r.fail({})}
    end

    def build_credentials(database, user, password)
      hosts = nodes.join(',')
      {
        # We use mongo_uri, because uri breaks staging
        mongo_uri: "mongodb://#{user}:#{password}@#{hosts}/#{database}",
        username: user,
        password: password,
        hosts: nodes,
        database: database
      }
    end

    def generate_database_name
      "d" + SecureRandom.base64(20).gsub(/[^a-zA-Z0-9]+/, '')[0...16]
    end

    def generate_user_name
      "u" + SecureRandom.base64(20).gsub(/[^a-zA-Z0-9]+/, '')[0...16]
    end

    def generate_password
      "p" + SecureRandom.base64(20).gsub(/[^a-zA-Z0-9]+/, '')[0...16]
    end

    def to_mongo_password(login, password)
      Digest::MD5::hexdigest("#{login}:mongo:#{password}")
    end
  end
end
