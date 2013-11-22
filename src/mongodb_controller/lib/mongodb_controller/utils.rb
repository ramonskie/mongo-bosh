require 'em-mongo'

module VCAP::MongodbController
  module Utils
    def self.stringify_keys(hash)
      if hash.is_a? Hash
        Hash[hash.each_pair.map{|k, v| [k.to_s, stringify_keys(v)] }]
      else
        hash
      end
    end
  end
end

module EM::Mongo
  class Connection
    def callback(&block)
      @em_connection.callback(&block)
    end
  end
end

module VCAP::MongodbController
  class MongoCommand
    include EM::Deferrable

    def initialize(&command)
      @command = command
    end

    def call
      @command.call(self).timeout(60)
    rescue
      puts $!, $!.backtrace
      fail($!)
    ensure
      return self
    end

    def self.logger
      @@logger ||= Steno.logger("mc.command")
    end
  end

  class EmptyCommand
    include EM::Deferrable

    def initialize
      super
      succeed
    end
  end

  class MongodProcess < EventMachine::Connection
    def initialize(process, port)
      @process = process
      @port = port
    end

    def post_init
      @process.started
    end

    def receive_data(data)
      #puts "#{@port}: #{data}"
    end

    def stop
      p [:stop. signature]
    end
  end
end
