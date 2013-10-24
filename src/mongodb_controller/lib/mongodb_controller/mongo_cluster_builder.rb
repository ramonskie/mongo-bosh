require 'socket'
require 'uri'
require_relative 'mongodb_driver'

module VCAP::MongodbController
  module MongoClusterBuilder
    class << self
      attr_reader :config, :message_bus

      def configure(config, message_bus)
        @config = config
        @message_bus = message_bus
        @mongodb_driver = MongodbDriver.new(config)
      end

      def run
        if main_node?
          message_bus.subscribe("mongodb.advertise") do |msg, reply|
            process_advertise_message(msg, reply)
          end
        else
          send_current_state
        end
      end

      def process_advertise_message(msg, reply)
        unless repl_set_status
          @mongo_driver.init_replication
        end

        if(@mongo_driver.replication_set.master?)
          puts "Adding member to cluster: #{msg.inspect}"
          @mongo_driver.replication_set.add_member(msg["ip"])
        end
      rescue
        puts $!, $!.backtrace
      end

      private
      def send_current_state
        @mongo_session = ::Mongo::MongoClient.new('127.0.0.1', 27017)

        state = repl_set_status
        unless state
          message_bus.publish("mongodb.advertise", ip: local_ip)
        end
      end

      def local_ip
        target = URI(config[:message_bus_uri]).host
        @local_ip ||= UDPSocket.open {|s| s.connect(target, 1); s.addr.last}
      end
    end
  end
end
