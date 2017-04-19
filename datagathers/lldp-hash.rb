#!/usr/bin/env ruby

require 'timeout'
require 'pp'

lldp = Hash.new

ENV["PATH"]="/bin:/sbin:/usr/bin:/usr/sbin"

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
          lldp.store(key, value)
        }
      end
      pp lldp
    end
  }
rescue Timeout::Error
  ""
end

exit
