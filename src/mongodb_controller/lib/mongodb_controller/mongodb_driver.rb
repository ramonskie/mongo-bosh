require 'em-mongo'
require 'socket'
require 'uri'
require_relative 'utils'


module VCAP::MongodbController
  class MongodbDriver
    attr_reader :state, :connection

    def initialize(config)
      @global_config = config
      @state = :stopped
    end

    def logger
      @logger ||= Steno.logger("mc.driver")
    end

    def start
      return unless state == :stopped
      @commands = []
      @process = EM.popen(mongod_cmdline, MongodProcess, self, @global_config[:mongod_port])
      @state = :starting
    end

    def stop
      @state = :stopped
      @process.stop if @process
    end

    def started
      @state = :started
      @connection = EM::Mongo::Connection.new("127.0.0.1", @global_config[:mongod_port],
                                              20, reconnect_in: 30)
      @connection.callback { process_commands }
    rescue
      logger.log_exception $!
    end

    def run_on_mongo(&block)
      MongoCommand.new(&block).tap{|command| @commands << command }
    end

    def update_config(node_config)
      File.open(@global_config[:mongod_config_file], "w") do |f|
        f.puts generate_config(node_config)
      end
    end

    protected
    def process_commands
      unless @commands.empty?
        command = @commands.shift
        command.call.
          callback { process_commands }.
          errback {|e| logger.error(e, e); process_commands }
      else
        EM.add_timer(1) { process_commands }
      end
    rescue
      logger.log_exception $!
      EM.add_timer(1) { process_commands }
    end

    def generate_config(node_config)
      <<END_CONFIG
syslog = #{not test_mode?}
dbpath=#{@global_config[:mongod_data_dir]}
keyFile=#{@global_config[:mongo_key_file]}

directoryperdb=true

replSet=#{node_config[:replication_set] || "rs0" }
port=#{@global_config[:mongod_port]}

vvvvv=true
noprealloc=#{test_mode?}
smallfiles=#{test_mode?}
nopreallocj=#{test_mode?}
END_CONFIG
    end

    def test_mode?
      !!ENV['TEST_MODE']
    end

    def mongod_cmdline
      [@global_config[:mongod_binary], "--config", @global_config[:mongod_config_file]]
    end

  end
end
