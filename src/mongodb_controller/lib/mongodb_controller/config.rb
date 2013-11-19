require "vcap/config"
require "uri"

# Config template for cloud controller
class VCAP::MongodbController::Config < VCAP::Config
  define_schema do
    {
      message_bus_uri:    String,  # Currently a NATS uri of the form nats://<user>:<pass>@<host>:<port>
      pid_filename:       String,  # Pid filename to use
      master_node:        bool,    # Is this node is master node# (first node)
      node_config_file:   String,  # Configuration file with node configuration
      mongod_config_file: String,  # MongoDB configuration file storage path
      mongod_port:        Integer, # Port for startup MongoDB
      mongod_binary:      String,  # Path to MongoDB binary
      mongod_data_dir:    String,  # Path to MongoDB data directory
    }
  end

  def initialize(config)
    @config = config
  end

  def master_node?
    @config[:master_node]
  end

  def [](key)
    @config[key]
  end

  class << self
    def from_file(file_name)
      self.new(super(file_name))
    end

    attr_reader :config, :message_bus

    def configure(config, message_bus)
      @config = config
      @message_bus = message_bus
    end

    def config_dir
      @config_dir ||= File.expand_path("../../../etc", __FILE__)
    end
  end
end
