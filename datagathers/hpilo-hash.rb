#!/usr/bin/env ruby

require 'pp'
require 'timeout'
require 'rexml/document'
include REXML

# Can't use the iLO Get/Set commands because then rubbishy
# hponcfg adds a seemingly arbitrary sleep 5 at the end
# (after outputting the data).
#

hpilo = Hash.new

return '' unless File.executable?('/sbin/hponcfg') == true

ENV["PATH"]="/bin:/sbin:/usr/bin:/usr/sbin"
fname = "/var/tmp/ilodata." + $$.to_s
ok = false
begin
  tstatus = Timeout::timeout(10) {
    IO.foreach("|hponcfg -w #{fname} 2>/dev/null") { |line|
      line.chomp
      if line =~ /^Firmware/ then
        fwver = (line.split)[3]
        type = (line.split)[8]
        if type == 'Driver' then
          ilotype = "iLO1"
        else
          ilotype = "iLO" + type
        end
        hpilo.store("firmware_version", fwver)
        hpilo.store("type", ilotype)
      end
      ok = true if line =~ /successfully written/
    }
  }
  rescue Timeout::Error
    ""
end

doc = Document.new(File.new(fname))
network_settings = doc.root.elements["LOGIN"].elements["RIB_INFO"].elements["MOD_NETWORK_SETTINGS"]
ip = network_settings.elements["IP_ADDRESS"].attributes["VALUE"]
shorthost = network_settings.elements["DNS_NAME"].attributes["VALUE"]
longhost = shorthost + "." + network_settings.elements["DOMAIN_NAME"].attributes["VALUE"]
gateway = network_settings.elements["GATEWAY_IP_ADDRESS"].attributes["VALUE"]
File.delete(fname)

hpilo.store("ip", ip)
hpilo.store("short_hostname", shorthost)
hpilo.store("host_fqdn", longhost)
hpilo.store("gateway", gateway)

pp hpilo
