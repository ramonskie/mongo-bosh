module VCAP::MongodbController
  module Utils
    def self.stringify_keys(hash)
      if hash.is_a? Hash
        Hash[hash.each_pair.map{|k, v| [k.to_s, stringify_keys(v)] }]
      else
        hash
      end
    end
  end
end

require 'em-mongo'
module EM::Mongo
  class Connection
    def callback(&block)
      @em_connection.callback(&block)
    end
  end
end
