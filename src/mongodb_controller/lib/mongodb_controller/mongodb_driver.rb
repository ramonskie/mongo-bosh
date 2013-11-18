require 'em-mongo'
require 'socket'
require 'uri'
require_relative 'utils'

module VCAP::MongodbController
  class MongodbDriver
    attr_reader :state

    def initialize(config)
      @global_config = config
      @state = :stopped
    end

    def start
      unless node_config[:configured?]
        apply_config(master: true, configured?: true) if @global_config.master_node?
      end
      if !node_config[:configured?]
        puts "Postponing startup for slave node"
      else
        start_mongo
      end
    end

    def stop
      @state = :stopped
    end

    def node_config
      @node_config ||= load_node_config
      @node_config.merge(ip: local_ip, port: @global_config[:mongod_port])
    end

    def started
      @state = :started
      @connection = EM::Mongo::Connection.new("127.0.0.1", @global_config[:mongod_port],
                                              3, reconnect_in: 3)
      @connection.callback { process_commands }
      run_on_mongo { mongo_apply_config }
    rescue
      p $!, $!.backtrace
    end

    def apply_config(node_config)
      update_config(node_config)
      stop
      start
    end

    def register_member(host, port)
      run_on_mongo { add_member("#{host}:#{port}") }
    end

    protected
    def process_commands
      EM.add_timer(1) do
        begin
          unless @commands.empty?
            @commands.shift.call
          end
        rescue
          puts $!, $!.backtrace
        end
        process_commands
      end
    end

    def run_on_mongo(&block)
      @commands << block
    end

    def update_config(node_config)
      File.open(@global_config[:mongod_config_file], "w") do |f|
        f.puts generate_config(node_config)
      end
      self.node_config = node_config
    end

    def start_mongo
      return unless state == :stopped
      @commands = []
      @process = EM.popen(mongod_cmdline, MongodProcess, self, @global_config[:mongod_port])
      @state = :starting
    end

    def generate_config(node_config)
      <<END_CONFIG
syslog = #{not test_mode?}
pidfilepath=#{@global_config[:pid_filename]}
dbpath=#{@global_config[:mongod_data_dir]}

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

    def local_ip
      target = URI(@global_config[:message_bus_uri]).host
      @local_ip ||= UDPSocket.open {|s| s.connect(target, 1); s.addr.last}
    end

    def node_config=(node_config)
      File.open(@global_config[:node_config_file], "w") do |f|
        f.puts(YAML.dump(Utils.stringify_keys(node_config)))
      end
      @node_config = node_config
    end

    def load_node_config
      config = YAML.load_file(@config[:node_config_file]) rescue {}
      VCAP.symbolize_keys(config)
    end

    def mongod_cmdline
      [@global_config[:mongod_binary], "--config", @global_config[:mongod_config_file]]
    end

    def mongo_apply_config
      if @node_config[:master]
        replication_set.callback do |s|
          puts [:config, s]
          unless s
            init_replication
          end
        end
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
    end

    def replication_set
      @connection.db(:local).collection('system.replset').find_one
    end

    def status
      @connection.db(:admin).command(replSetGetStatus: 1)
    end

    def init_replication
      config = {_id: node_config[:replication_set] || "rs0",
        members: [{_id: 1, host: "#{local_ip}:#{@global_config[:mongod_port]}"}]}
      @connection.db(:admin).command(replSetInitiate: config).errback{|e| p e}
    end

    def replication_set_status
      @connection.db(:local).collection('system.replset').find_one
    end

    def add_member(host)
      when_replication_available do
        replication_set.callback do |s|
          begin
            set = Hash[s]
            max_version = set['members'].map{|h| h["_id"]}.max
            set['members'] << { _id: max_version + 1, host: host }
            set['version'] += 1

            @connection.db(:admin).command(replSetReconfig: set).callback{|d| p [:ok, d]}.errback{|e| p e}
          rescue
            puts $!, $!.backtrace
          end
        end
      end
    end

    def when_replication_available(&block)
      status.callback do |s|
        if s["myState"] == 1
          yield
        else
          EM.add_timer(1) { when_replication_available(&block) }
        end
      end.errback { EM.add_timer(1) { when_replication_available(&block)} }
    end
  end
end
