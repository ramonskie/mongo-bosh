require_relative 'mongodb_driver'

module VCAP::MongodbController
  class MongoClusterBuilder
    ADVERTIZE_CHANNEL = "mongodb.advertise".freeze
    PROVISION_CHANNEL = "mongodb.provision".freeze

    attr_reader :config, :message_bus, :driver, :node_config

    def initialize(config, message_bus, node_config, driver = MongodbDriver.new(config))
      @config = config
      @message_bus = message_bus
      @driver = driver
      @node_config = node_config
    end

    def logger
      @logger ||= Steno.logger("mc.cluster_builder")
    end

    def run
      if master_node?
        attach_as_master
      else
        advertise_slave
      end
    end

    private
    def master_node?
      config.master_node?
    end

    def advertise_slave
      logger.info "Attaching as slave"
      message_bus.request(ADVERTIZE_CHANNEL,
                          node_config.merge(ip: local_ip, port: config[:mongod_port])) do |r|
        response = VCAP.symbolize_keys(r)
        case response[:command]
        when "update_config" then apply_config(response[:data])
        end
      end
    end

    def attach_as_master
      logger.info "Attaching as master"
      message_bus.subscribe(ADVERTIZE_CHANNEL) do |msg, reply|
        process_advertise_message(msg, reply)
      end

      unless node_config[:configured?]
        apply_config(master: true, configured?: true,
                     nodes: ["#{local_ip}:#{config[:mongod_port]}"])
      end
      start_mongo
      driver.run_on_mongo {|r| mongo_apply_config(r) }
    end

    def start_mongo
      if !node_config[:configured?]
        logger.debug "Postponing startup while not configured"
      else
        driver.start
      end
    end

    def apply_config(node_config)
      driver.update_config(node_config)
      self.node_config.update do |c|
        c.replace(node_config)
      end
      driver.stop
      driver.start
    end


    def process_advertise_message(msg, reply)
      logger.info "Processing message", msg
      data = {
        replication_set: node_config[:replication_set] || 'rs0',
        configured?: true
      }
      register_member(msg["ip"], msg["port"])
      message_bus.publish(reply, {command: "update_config", data: data})
    end

    # Processing logic for messages
    def mongo_apply_config(r)
      if node_config[:master]
        replication_set.callback do |s|
          logger.info "Applying master config", s
          init_replication("#{local_ip}:#{@config[:mongod_port]}").
                           callback{ logger.error("Replication initialized");r.succeed }.
                           errback{|e| logger.error("Error initialize replication", e); r.failed(e) }
        end
      else
        r.succeed
      end
    end

    def register_member(host, port)
      driver.run_on_mongo {|r| add_member(r, "#{host}:#{port}") }
    end

    def add_member(r, host)
      when_replication_available do
        replication_set.callback do |s|
          begin
            set = Hash[s]
            max_version = set['members'].map{|h| h["_id"]}.max
            set['members'] << { _id: max_version + 1, host: host }
            set['version'] += 1

            driver.connection.db(:admin).command(replSetReconfig: set).
              callback do |d|
              logger.info("Replication node added", set)
              node_config.update do |c|
                c[:nodes] << host
              end
              r.succeed
            end.
              errback{|e| logger.info "Error adding replication node", [set, e].inspect }
          rescue
            logger.log_exception $!, s
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

    def replication_set
      driver.connection.db(:local).collection('system.replset').find_one
    end

    def status
      driver.connection.db(:admin).command(replSetGetStatus: 1)
    end

    def init_replication(local_host)
      config = {_id: node_config[:replication_set] || "rs0",
        members: [{_id: 1, host: local_host}]}
      driver.connection.db(:admin).command(replSetInitiate: config).
        errback{|e| logger.error("Error initializing replication", e)}
    end

    def replication_set_status
      driver.connection.db(:local).collection('system.replset').find_one
    end

    def local_ip
      target = URI(@config[:message_bus_uris].first).host
      @local_ip ||= UDPSocket.open {|s| s.connect(target, 1); s.addr.last}
    end
  end
end
