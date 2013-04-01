require 'nagiosplugin'
require 'uuidtools'
require 'open3'

# TODO
# - options
# - set ENV["PATH"]

class NSCA < NagiosPlugin::Plugin
  @@icinga_log = "/var/spool/icinga/icinga.log"
  def self.icinga_log
    @@icinga_log
  end

  def check
    Thread.abort_on_exception = true
    timeout = 10
    uuid = UUIDTools::UUID.timestamp_create
    reader_thread = Thread.new do
      stdin, stdout, stderr, wait_thr = Open3.popen3("tail -f #{NSCA.icinga_log}")
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
        raise "command tail exited with \"%s\"" % [ stderr.readlines.join.chomp ]
      end
      stderr.close
      stdout.close
      raise "cannot find #{uuid.to_s}" unless found
    end

    send_probe(uuid.to_s)
    thread = reader_thread.join(timeout)
    if thread.nil?
      critical("could not find %s in %s" % [ uuid.to_s, NSCA.icinga_log ])
    end
    ok("found %s in %s" % [ uuid.to_s, NSCA.icinga_log ])
  end

  def send_probe(text = "")
    cmd = "/usr/local/sbin/send_nsca -H localhost -c /usr/local/etc/nagios/send_nsca.cfg"
    stdin, stdout, stderr, wait_thr = Open3.popen3(cmd)
    pid = wait_thr[:pid]
    message = sprintf "%s\t%s\t%s\t%s\n" % [ "icinag.jp.reallyenglish.com", "check_nsca_local", "0", text ]
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

NSCA.run
