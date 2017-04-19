require 'facter'

pcislots = Hash.new

lspci = "/sbin/lspci"

exit 0 if lspci.empty? # If we cannot find an lspci binary what would be the point ?

def add_fact(fact, code)
  Facter.add(fact) { setcode { code } }
end

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

  counter = 0
  #devices.each_key do |a|
  devices.each_pair do |k, v|
    # Only report if it's shown as in a physical slot. This won't work on RHEL5...
    slotphys = v['PhySlot']
    if !slotphys.nil?
      #add_fact("pci_slot_id_#{k}", k)
      slotdrv = v['Driver']
      if !slotdrv.nil?
        # add_fact("pci_slot_id_#{k}_driver", slotdrv)
        add_fact("pci_slot_id_#{k}_driver", slotdrv)
      end
      slotcls = v['Class']
      if !slotcls.nil?
        add_fact("pci_slot_id_#{k}_class", slotcls)
      end
      slotven = v['Vendor']
      if !slotven.nil?
        add_fact("pci_slot_id_#{k}_vendor", slotven)
      end
      slotdev = v['Device']
      if !slotdev.nil?
        add_fact("pci_slot_id_#{k}_device", slotdev)
      end
      slotsdev = v['SDevice']
      if !slotsdev.nil?
        if slotsdev != slotdev
          add_fact("pci_slot_id_#{k}_sdevice", slotsdev)
        end
      end
      slotsven = v['SVendor']
      if !slotsven.nil?
      if slotsven != slotven
        add_fact("pci_slot_id_#{k}_svendor", slotsven)
      end
    end
      add_fact("pci_slot_id_#{k}_physical_slot", slotphys)
      IO.foreach("|/sbin/lspci -vv -s #{k}") { |line|
        line.chomp
        if line.include? "LnkSta:"
          info = line.split
          slot_speed = "#{info[2]}".chomp.gsub(",", "")
          slot_width = "#{info[4]}".chomp.gsub(",", "")
          add_fact("pci_slot_id_#{k}_slot_speed", slot_speed)
          add_fact("pci_slot_id_#{k}_slot_width", slot_width)
        end
        if line.include? "Part number:"
          pnum = line.split
          partnum = "#{pnum[3]}".chomp
          add_fact("pci_slot_id_#{k}_part_num", partnum)
        end
        if line.include? "Serial number:"
          snum = line.split
          serialnum = "#{snum[3]}".chomp
          add_fact("pci_slot_id_#{k}_serial_num", serialnum)
        end
      }
    end
    counter +=1
  end
end
