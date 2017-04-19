require 'timeout'
require 'pp'

ENV["PATH"]="/bin:/sbin:/usr/bin:/usr/sbin"

lldp = Hash.new

def add_fact(fact, code)
    Facter.add(fact) { setcode { code } }
end

begin
  tstatus = Timeout::timeout(15) {
    if FileTest.socket?('/var/run/lldpd.socket')
      if File.executable?('/usr/sbin/lldpctl')
        lldp_cmd = "lldpctl -f keyvalue"

        IO.foreach("|#{lldp_cmd}") { |line|
          line.chomp
          lldp_data = line.split('=')
          key = "#{lldp_data[0]}".chomp
          value = "#{lldp_data[1]}".chomp
          add_fact(key,value)
        }
      end

    end
  }
rescue Timeout::Error
  ""
end
