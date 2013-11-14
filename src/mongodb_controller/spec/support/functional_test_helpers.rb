require 'sys/proctable'
require 'tempfile'
require 'active_support/core_ext/numeric/time'
require 'socket'

module FunctionalTestHelper
  def process_list(process)
    Sys::ProcTable.ps.find_all{|p| p.exe == process}.sort_by(&:pid).
      map{|p| {id: p.pid, exe: p.exe, cmdline: p.cmdline} }
  end

  def create_server_process(config)
    ControlledProcess.new([server_path, '--config', config])
  end

  def server_path
    File.absolute_path(File.join(File.dirname(__FILE__), "../../bin/mongodb_controller"))
  end

  def create_node_config(options = {})
    MongodConfig.new({mongod_path: mongod_path, port: next_port}.merge(options))
  end

  def create_nats_process
    ControlledProcess.new([nats_server_path])
  end

  def mongod_path
    ENV["MONGOD_PATH"] || '/usr/bin/mongod'
  end

  def nats_server_path
    ENV["NATS_PATH"] || 'nats-server'
  end

  def next_port
    @next_port= @next_port ? @next_port + 1 : 27020
  end

  def wait_timeout(message = "Expectation not met", timeout = 60.seconds)
    start = Time.now

    while(Time.now < start + timeout)
      begin
        return if yield
      rescue
        puts $!, $!.backtrace
      end
      sleep 1
    end
    raise RSpec::Expectations::ExpectationNotMetError.new(message)
  end

  class ControlledProcess
    def initialize(cmdline)
      @cmdline = cmdline
    end

    def start
      @pid = spawn(*@cmdline)
    end

    def stop
      Process.kill("TERM", @pid)
      Process.wait(@pid)
    end

    def wait_startup(port, timeout = 60.seconds)
      start_time = Time.now

      while(Time.now < start_time + timeout)
        begin
          s = TCPSocket.new('127.0.0.1', port)
          s.close
          return true
        rescue
          p "waiting connect to port #{port}..."
          sleep 1
        end
      end
      raise RSpec::Expectations::ExpectationNotMetError.new("Can't connect to target port")
    end
  end

  class MongodConfig
    def initialize(config)
      @tempfile = Tempfile.new("config")
      @config = config
      create_config
    end

    def create_config
      conf = {
        message_bus_uri: 'nats://user:password@127.0.0.1:4222',
        pid_filename: "/tmp/pid_#{port}",
        master_node: master?,
        node_config_file: node_config_file,
        mongod_config_file: mongod_config_file,
        mongod_port: port,
        mongod_binary: mongod_path,
        mongod_data_dir: mongod_data_dir
      }
      cleanup
      FileUtils.mkdir_p mongod_data_dir
      @tempfile.write(YAML.dump(conf))
      @tempfile.close
    end

    def mongod_data_dir
      "/tmp/test-#{port}"
    end

    def mongod_config_file
      "/tmp/mongo_#{port}.conf"
    end

    def node_config_file
      "/tmp/node_#{port}.yml"
    end

    def port
      @config[:port]
    end

    def path
      @tempfile.path
    end

    def mongod_path
      @config[:mongod_path]
    end

    def master?
      @config[:master] || false
    end

    def cleanup
      FileUtils.rm_rf mongod_data_dir rescue nil
      File.unlink mongod_config_file rescue nil
      File.unlink node_config_file rescue nil
    end

    def unlink
      @tempfile.unlink
      cleanup
    end
  end
end

RSpec.configure { |c| c.include FunctionalTestHelper }
