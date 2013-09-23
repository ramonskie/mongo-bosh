require 'socket'
require 'uri'
require 'mongo'

module VCAP::MongodbController
  module MongoClusterBuilder
    class << self
      attr_reader :config, :message_bus

      def configure(config, message_bus)
        @config = config
        @message_bus = message_bus
      end

      def run
        message_bus.subscribe("mongodb.advertise") do |msg, reply|
          process_advertise_message(msg, reply)
        end

        send_current_state
      end

      def process_advertise_message(msg, reply)
        p [:got_message, msg]
        unless repl_set_status
          @mongo_session['admin'].command(replSetInitiate: 1) rescue nil
        end

        if(repl_set_master?)
          puts "Adding member to cluster: #{msg.inspect}"
          repl_set_add_member(msg["ip"])
        end
      rescue
        puts $!, $!.backtrace
      end

      private

      def repl_set_status
        @mongo_session['local']['system.replset'].find_one
      end

      def repl_set_add_member(host)
        set = Hash[repl_set_status.to_a]
        p [:prevConfig, set]
        max_version = set['members'].map{|h| h["_id"]}.max
        set['members'] << { _id: max_version + 1, host: host }
        set['version'] += 1
        
        p [:newConfig, set]
        @mongo_session['admin'].command(replSetReconfig: set)
      end

      def repl_set_master?
        @mongo_session['admin'].command(isMaster: 1)
      end

      def send_current_state
        @mongo_session = ::Mongo::MongoClient.new('127.0.0.1', 27017)

        state = repl_set_status
        p [:state, state]
#        unless state
          message_bus.publish("mongodb.advertise", ip: local_ip)
#        end
      end

      def local_ip
        target = URI(config[:message_bus_uri]).host
        @local_ip ||= UDPSocket.open {|s| s.connect(target, 1); s.addr.last}
      end
    end
  end
end
