require 'optparse'
require 'steno'
require 'eventmachine'
require 'cf_message_bus/message_bus'
require 'thin'
require_relative 'config'
require_relative 'mongodb_broker'

module MongodbSeviceBroker
  class Runner
    def initialize(argv)
      @argv = argv

      @config_file = File.expand_path('../../config/mongodb_broker.yml', __FILE__)
      parse_options!
      parse_config

      setup_logging
    end

    def options_parser
      @parser ||= OptionParser.new do |opts|
        opts.on('-c', '--config [ARG]', 'Configuration File') do |opt|
          @config_file = opt
        end
      end
    end

    def logger
      @logger ||= Steno.logger('msb.runner')
    end

    def parse_options!
      options_parser.parse! @argv
    rescue
      puts options_parser
      exit 1
    end

    def parse_config
      @config = MongodbSeviceBroker::Config.from_file(@config_file)
    rescue Membrane::SchemaValidationError => ve
      puts "ERROR: There was a problem validating the supplied config: #{ve}"
      exit 1
    rescue => e
      puts "ERROR: Failed loading config from file '#{@config_file}': #{e}"
      exit 1
    end

    def setup_logging
      steno_config = Steno::Config.to_config_hash(@config[:logging])
      steno_config[:context] = Steno::Context::ThreadLocal.new
      Steno.init(Steno::Config.new(steno_config))
    end

    def run!
      create_pidfile
      trap_signals

      EM.run do
        start_app
      end
      traps.each(&:call)
    end

    def trap_signals
      %w(TERM INT QUIT).each do |signal|
        trap(signal) do
          add_trap do
            logger.warn("Caught signal #{signal}")
          end
          stop!
        end
      end
    end

    def stop!
      @thin_server.stop!
      EM.stop
    end

    def create_pidfile
      pid_file = VCAP::PidFile.new(@config[:pid_filename])
      pid_file.unlink_at_exit
    rescue
      puts "ERROR: Can't create pid file #{@config[:pid_filename]}"
      exit 1
    end

    private
    def start_app
      @message_bus = CfMessageBus::MessageBus.new(uris: @config[:message_bus_uris],
                                                  logger: Steno.logger('mc.bus'))
      MongodbBroker.configure(@config, @message_bus)
      @thin_server = Thin::Server.new(@config[:bind_address], @config[:port], signals: false)
      @thin_server.app = MongodbBroker
      @thin_server.timeout = 10
      @thin_server.threaded = true
      @thin_server.start!
    end

    def traps
      @traps ||= []
    end

    def add_trap(&block)
      traps << block
    end
  end
end
