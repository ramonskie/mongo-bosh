require 'mongo'

module VCAP::MongodbController
  class MongodbDriver
    attr_reader :config

    def initialize(config)
      @config = config
    end

    def init_replication
      session['admin'].command(replSetInitiate: 1) rescue nil
    end

    def replication_set_status
      session['local']['system.replset'].find_one
    end

    def replication_set
      @replication_set ||= ReplicationSet.new(session)
    end

    protected
    def session
      @session ||= ::Mongo::MongoClient.new('127.0.0.1', 27017)
    end

    class ReplicationSet
      attr_reader :session

      def initialize(session)
        @session = session
      end

      def status
        session['local']['system.replset'].find_one
      end

      def add_member(host)
        set = Hash[status.to_a]
        max_version = set['members'].map{|h| h["_id"]}.max
        set['members'] << { _id: max_version + 1, host: host }
        set['version'] += 1

        session['admin'].command(replSetReconfig: set)
      end

      def master?
        session['admin'].command(isMaster: 1)
      end
    end
  end
end
