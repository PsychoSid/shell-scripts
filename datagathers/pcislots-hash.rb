#!/usr/bin/env ruby

pcislots = Hash.new

lspci = "/sbin/lspci"

exit 0 if lspci.empty? # If we cannot find an lspci binary what would be the point ?

if FileTest.exists?(lspci)
  # Create a hash of all objects
  # { SLOT_ID -> { ATTRIBUTE => VALUE }, ...}
  slot=""
  devices = {}
  %x{#{lspci} -v -mm -k 2>&1}.each_line do |line|
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

  pci_file = '/etc/facter/facts.d/pci_facts.txt'
  if File.exist?(pci_file) then
    File.delete(pci_file)
  end
  open(pci_file, 'a') do |f|
    #devices.each_key do |a|
    devices.each_pair do |k, v|
      slotphys = v['PhySlot']
      if !slotphys.nil?
        #pcislots.store("pci_slot_id_#{k}", k)
        slotdrv = v['Driver']
        if !slotdrv.nil?
          f.puts "pci_slot_id_#{k}_driver=#{slotdrv}"
        end
        slotcls = v['Class']
        if !slotcls.nil?
          f.puts "pci_slot_id_#{k}_class=#{slotcls}"
        end
        slotven = v['Vendor']
        if !slotven.nil?
          f.puts "pci_slot_id_#{k}_vendor=#{slotven}"
        end
        slotdev = v['Device']
        if !slotdev.nil?
          f.puts "pci_slot_id_#{k}_device=#{slotdev}"
        end
        slotsdev = v['SDevice']
        if !slotsdev.nil?
          f.puts "pci_slot_id_#{k}_sdevice=#{slotsdev}"
        end
        slotsven = v['SVendor']
        if !slotsven.nil?
          f.puts "pci_slot_id_#{k}_svendor=#{slotsven}"
        end
        slotphys = v['PhySlot']
        if !slotphys.nil?
          f.puts "pci_slot_id_#{k}_physical_slot=#{slotphys}"
          IO.foreach("|/sbin/lspci -vv -s #{k} 2>&1") { |line|
            line.chomp
            if line.include? "LnkSta:"
              info = line.split
              slot_speed = "#{info[2]}".chomp.gsub(",", "")
              slot_width = "#{info[4]}".chomp.gsub(",", "")
              f.puts "pci_slot_id_#{k}_slot_speed=#{slot_speed}"
              f.puts "pci_slot_id_#{k}_slot_width=#{slot_width}"
            end
            if line.include? "Part number:"
              pnum = line.split
              partnum = "#{pnum[3]}".chomp
              f.puts "pci_slot_id_#{k}_part_num=#{partnum}"
            end
            if line.include? "Serial number:"
              snum = line.split
              serialnum = "#{snum[3]}".chomp
              f.puts "pci_slot_id_#{k}_serial_num=#{serialnum}"
            end
          }
        end
      end
    end
  end
end
