require 'observer'

class UpdatableConfig
  include Observable

  def initialize(file_path, default_data = {})
    @data = default_data
    @file_path = file_path
    if File.exists?(file_path)
      File.open(file_path, 'r') do |f|
        @data = YAML.load(f.read)
      end
    end
  rescue
    logger.log_exception $!
  ensure
    @mutex = Mutex.new
  end

  def update
    @mutex.synchronize do
      data = YAML.dump(@data)
      r = yield @data
      updated_data = YAML.dump(@data)
      if data != updated_data
        changed
        File.open(@file_path, "w") do |f|
          f.puts updated_data
        end
        notify_observers @data
      end
      r
    end
  end

  def notify_observers!
    changed
    notify_observers @data
  end

  def [](key)
    @data[key]
  end

  def merge(hash)
    @data.merge(hash)
  end

  def logger
    @logger ||= Steno.logger("mc.updatable_config")
  end
end
