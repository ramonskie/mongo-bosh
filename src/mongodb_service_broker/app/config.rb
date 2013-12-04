require "vcap/config"

# Config template for cloud controller
module MongodbSeviceBroker
  class Config < VCAP::Config
    define_schema do
      {
        message_bus_uris:   Array,   # List of NATS uris of the form nats://<user>:<pass>@<host>:<port>
        pid_filename:       String,  # Pid filename to use
        bind_address:       String,  # Address for bind webserver
        port:               Integer, # Port for bind webserver
        login:              String,  # Login for service brocker
        password:           String,  # Password for service brocker
        optional(:index) => Integer, # Component index (cc-0, cc-1, etc)
        external_domain:    String,  # App external domain
      }
    end

    def initialize(config)
      @config = config
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
end
