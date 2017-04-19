#!/usr/bin/env ruby

require 'pp'

mellanox = Hash.new

lspci = "/sbin/lspci"

exit 0 if lspci.empty? # If we cannot find an lspci binary what would be the point ?

if File.directory?("/sys/bus/pci/drivers/mlx4_core")
  mlx = %x{lspci | grep Mellanox | sort}
  mellanox_pciids = mlx.scan(/^(\S+)/)
  mellanox.store("mellanox_busids", mellanox_pciids.join(","))

  if FileTest.exists?(lspci)
    # Create a hash of all objects
    # { SLOT_ID -> { ATTRIBUTE => VALUE }, ...}
    slot=""
    devices = {}
    %x{#{lspci} -v -mm -k}.each_line do |line|
      if not line =~ /^$/ # any empty lines throw away
        splitted = line.split(/\t/)
        if splitted[0] =~ /^Slot:$/
          slot=splitted[1].chomp
          devices[slot] = {}
        else
          devices[slot][splitted[0].chop] = splitted[1].chomp
        end
      end
    end

    ofed_counter = 0
    devices.each_key do |a|
      if a.empty?
        exit 0
      else
        case devices[a].fetch("Vendor")
        when /^Mellanox/
          mellanox.store("mellanox_card#{ofed_counter}_drv", "#{devices[a].fetch('Driver')}")
          mellanox.store("mellanox_card#{ofed_counter}_dev", "#{devices[a].fetch('Device')}")
          ofed_counter +=1
        end
      end
    end
  end
  pp mellanox
end
