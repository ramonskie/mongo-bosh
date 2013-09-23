require "vcap/config"
require "uri"

# Config template for cloud controller
class VCAP::MongodbController::Config < VCAP::Config
  define_schema do
    {
      :message_bus_uri              => String,     # Currently a NATS uri of the form nats://<user>:<pass>@<host>:<port>
      :pid_filename          => String,     # Pid filename to use
    }
  end


  class << self
    def from_file(file_name)
      config = super(file_name)
    end

    attr_reader :config, :message_bus

    def configure(config, message_bus)
      @config = config
      @message_bus = message_bus
      VCAP::MongodbController::MongoClusterBuilder.configure(config, message_bus)
    end

    def config_dir
      @config_dir ||= File.expand_path("../../../etc", __FILE__)
    end
  end
end
