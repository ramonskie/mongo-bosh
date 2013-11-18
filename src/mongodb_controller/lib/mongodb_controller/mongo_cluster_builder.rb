require_relative 'mongodb_driver'

module VCAP::MongodbController
  module MongoClusterBuilder
    ADVERTIZE_CHANNEL = "mongodb.advertise".freeze
    class << self
      attr_reader :config, :message_bus

      def configure(config, message_bus, driver = MongodbDriver.new(config))
        @config = config
        @message_bus = message_bus
        @mongodb_driver = driver
      end

      def run
        if master_node?
          attach_as_master
        else
          advertise_slave
        end
      rescue
        puts $!, $!.backtrace
      end

      private
      def master_node?
        config.master_node?
      end

      def advertise_slave
        message_bus.request(ADVERTIZE_CHANNEL, @mongodb_driver.node_config) do |r|
          response = VCAP.symbolize_keys(r)
          case response[:command]
          when "update_config" then @mongodb_driver.apply_config(response[:data])
          end
        end
      end
      def attach_as_master
        message_bus.subscribe(ADVERTIZE_CHANNEL) do |msg, reply|
          process_advertise_message(msg, reply)
        end

        @mongodb_driver.start
      end

      def process_advertise_message(msg, reply)
        data = {
          replication_set: @mongodb_driver.node_config[:replication_set] || 'rs0',
          configured?: true
        }
        @mongodb_driver.register_member(msg["ip"], msg["port"])
        NATS.publish(reply, {command: "update_config", data: data}.to_json)
      end
    end
  end
end
