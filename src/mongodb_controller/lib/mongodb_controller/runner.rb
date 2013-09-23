require "steno"
require "optparse"
require "cf_message_bus/message_bus"

require_relative "message_bus_configurer"
require_relative "mongo_cluster_builder"

module VCAP::MongodbController
  class Runner
    def initialize(argv)
      @argv = argv

      # default to production. this may be overriden during opts parsing
      @config_file = File.expand_path("../../../config/mongodb_controller.yml", __FILE__)
      parse_options!
      parse_config

      @log_counter = Steno::Sink::Counter.new
    end

    def logger
      @logger ||= Steno.logger("mc.runner")
    end

    def options_parser
      @parser ||= OptionParser.new do |opts|
        opts.on("-c", "--config [ARG]", "Configuration File") do |opt|
          @config_file = opt
        end
      end
    end

    def parse_options!
      options_parser.parse! @argv
    rescue
      puts options_parser
      exit 1
    end

    def parse_config
      @config = VCAP::MongodbController::Config.from_file(@config_file)
    rescue Membrane::SchemaValidationError => ve
      puts "ERROR: There was a problem validating the supplied config: #{ve}"
      exit 1
    rescue => e
      puts "ERROR: Failed loading config from file '#{@config_file}': #{e}"
      exit 1
    end

    def create_pidfile
      pid_file = VCAP::PidFile.new(@config[:pid_filename])
      pid_file.unlink_at_exit
    rescue
      puts "ERROR: Can't create pid file #{@config[:pid_filename]}"
      exit 1
    end

    def setup_logging
      steno_config = Steno::Config.to_config_hash(@config[:logging])
      steno_config[:context] = Steno::Context::ThreadLocal.new
      steno_config[:sinks] << @log_counter
      Steno.init(Steno::Config.new(steno_config))
    end

    def development?
      @development ||= false
    end

    def run!
      EM.run do
        config = @config.dup
        message_bus = MessageBusConfigurer::Configurer.new(uri: config[:message_bus_uri],
                                                           logger: logger).go
        start_mongodb_controller(message_bus)
        VCAP::MongodbController::MongoClusterBuilder.run
      end
    end

    def trap_signals
      %w(TERM INT QUIT).each do |signal|
        trap(signal) do
          logger.warn("Caught signal #{signal}")
          stop!
        end
      end
    end

    def stop!
      logger.info("Unregistering routes.")

      registrar.shutdown do
        stop_thin_server
        EM.stop
      end
    end


    private

    def start_mongodb_controller(message_bus)
      create_pidfile

      setup_logging

      VCAP::MongodbController::Config.configure(@config, message_bus)
    end
  end
end
