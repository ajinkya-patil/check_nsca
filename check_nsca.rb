#!__RUBY__
require 'rubygems'
require 'nagiosplugin'
require 'nagiosplugin/default_options'
require 'uuidtools'
require 'open3'

# TODO
# - -V reports wrong version
class NSCA < NagiosPlugin::Plugin

  include NagiosPlugin::DefaultOptions
  VERSION = 0.1

  class << self
    def run(*args)
      self.new(*args).run
    end
  end

  def parse_options(*args)
    @options = {}
    OptionParser.new do |opts|
      opts.on('--logfile file', String, 'File name of Nagios log file') do |s|
        @options[:logfile] = s
      end
      opts.on("-H", "--host hosname", String, "host to send_nsca (almost always default is fine") do |host|
        @options[:host] = host
      end
      opts.on("--nsca-cfg /path/to/send_nsca.cfg", String, "path to send_nsca.cfg") do |path|
        @options[:nscacfg] = path
      end

      yield(opts) if block_given?

      begin
        opts.parse!(args)
        @options
      rescue => e
        puts "#{e}\n\n#{opts}"
        exit(3)
      end
    end
  end

  def initialize(*args)
     parse_options(*args, &default_options)
     @logfile = @options[:logfile]
     # /var/spool/icinga/icinga.log
     if @logfile.nil? || @logfile.empty?
       case RbConfig::CONFIG['target_os']
       when /freebsd/
         @logfile = "/var/spool/icinga/icinga.log"
       else
         @logfile = "/var/spool/nagios/nagios.log"
       end
     end
     @nsca = @options[:nsca] || "send_nsca"
     @host = @options[:host] || "localhost"
     @nsca_cfg = @options[:nscacfg]
     if @nsca_cfg.nil? || @nsca_cfg.empty?
       case RbConfig::CONFIG['target_os']
       when /freebsd/
         @nsca_cfg = "/usr/local/etc/nagios/send_nsca.cfg"
       else
         @nsca_cfg = "/etc/nagios/send_nsca.cfg"
       end
     end
     ENV['PATH'] = "/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"
  end

  def check
    Thread.abort_on_exception = true
    timeout = 10
    uuid = UUIDTools::UUID.timestamp_create
    reader_thread = Thread.new do
      command = "tail -f #{@logfile}"
      stdin, stdout, stderr, wait_thr = Open3.popen3(command)
      stdin.close
      found = 0
      begin
        while line = stdout.readline.chomp do
          # [1364787960] EXTERNAL COMMAND: PROCESS_SERVICE_CHECK_RESULT;icinag.jp.reallyenglish.com;check_nsca_local;0;aa6bed40-9a7e-11e2-ac4d-002481a8dd5c
          ignore_me, log = line.split(": ", 2)
          nsca_value = log.split(";")[-1]
          if nsca_value == uuid.to_s
            found = 1
            break
          end
        end
      rescue EOFError => e
        raise "command \"%s\" exited with \"%s\"" % [ command, stderr.readlines.join.chomp ]
      end
      stderr.close
      stdout.close
      raise "cannot find #{uuid.to_s}" unless found
    end

    send_probe(uuid.to_s)
    thread = reader_thread.join(timeout)
    if thread.nil?
      critical("could not find %s in %s" % [ uuid.to_s, @logfile ])
    end
    ok("found %s in %s" % [ uuid.to_s, @logfile ])
  end

  def send_probe(text = "")
    cmd = "#{@nsca} -H #{@host} -c #{@nsca_cfg}"
    stdin, stdout, stderr, wait_thr = Open3.popen3(cmd)
    pid = wait_thr[:pid]
    message = sprintf "%s\t%s\t%s\t%s\n" % [ @host, "check_nsca_local", "0", text ]
    begin
      stdin.write(message)
    rescue Errno::EPIPE => e
    ensure
      stdin.close
    end
    exit_status = wait_thr.value
    # XXX send_nsca error goes to stdout
    raise "send_nsca failed with \"%s\"" % [ stdout.readlines.join.chomp ] unless exit_status == 0
    stdout.close
    stderr.close
  end
end

NSCA.run(*ARGV)
