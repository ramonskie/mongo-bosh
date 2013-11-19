require_relative 'mongodb_driver'

module VCAP::MongodbController
  module MongoClusterBuilder
    ADVERTIZE_CHANNEL = "mongodb.advertise".freeze
    PROVISION_CHANNEL = "mongodb.provision".freeze

    class << self
      attr_reader :config, :message_bus, :driver

      def configure(config, message_bus, driver = MongodbDriver.new(config))
        @config = config
        @message_bus = message_bus
        @driver = driver
      end

      def logger
        @logger ||= Steno.logger("mc.cluster_builder")
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
        logger.info "Attaching as slave"
        message_bus.request(ADVERTIZE_CHANNEL, driver.node_config) do |r|
          response = VCAP.symbolize_keys(r)
          case response[:command]
          when "update_config" then driver.apply_config(response[:data])
          end
        end
      end
      def attach_as_master
        logger.info "Attaching as master"
        message_bus.subscribe(ADVERTIZE_CHANNEL) do |msg, reply|
          process_advertise_message(msg, reply)
        end

        driver.start
      end

      def process_advertise_message(msg, reply)
        logger.info "Processing message", msg
        data = {
          replication_set: driver.node_config[:replication_set] || 'rs0',
          configured?: true
        }
        driver.register_member(msg["ip"], msg["port"])
        message_bus.publish(reply, {command: "update_config", data: data})
      end

      def process_provision_message(msg, reply)
        resp = case msg["command"]
               when "provision" then driver.provision
               else
                 raise "Unknown command"
               end
        message_bus.publish(reply, {error: false, data: resp})
      rescue
        logger.log_exception $!, "Provisioning error"
        message_bus.publish(reply, {error: true, message: $!.message})
      end
    end
  end
end
