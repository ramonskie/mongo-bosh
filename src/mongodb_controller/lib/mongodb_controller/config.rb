require "vcap/config"

# Config template for cloud controller
class VCAP::MongodbController::Config < VCAP::Config
  define_schema do
    {
      message_bus_uris:   Array,   # List of NATS uris of the form nats://<user>:<pass>@<host>:<port>
      pid_filename:       String,  # Pid filename to use
      master_node:        bool,    # Is this node is master node# (first node)
      node_config_file:   String,  # Configuration file with node configuration
      mongo_key_file:     String,  # Shared secred for MongoDB nodes
      provision_config:   String,  # Path to provision config file
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
  end
end
