require 'facter'

ENV["PATH"]="/bin:/sbin:/usr/bin:/usr/sbin:"

hostname = `hostname -s`.strip

ethernet = Hash.new

output=%x{lspci |grep Ethernet |sort}

busids = output.scan(/^(\S+)/)

ethernet.store("busids", busids)

def clean_key(key)
  key.gsub!(" ", "_")
  key.gsub!(".", "_")
  key.downcase!
  key.sub(/eth./) {|match| return "eith_#{match.scan(/eth.*/).last}"}
  key
end

def add_fact(fact, code)
    Facter.add(fact) { setcode { code } }
end

nicmods = Array.new
nicbusids = Array.new
modvers = Array.new
macs = Array.new
primarynic = nil
Dir.entries("/sys/class/net").sort.each { |nic|
  next if nic == '.' || nic == '..'
  next if nic =~ /^__tmp/
  next unless File.exists?("/proc/sys/net/ipv4/conf/#{nic}")
  primarynic = nic unless primarynic
  next unless nic[0,3] == 'eth'
  if File.exists?("/sys/class/net/#{nic}/device/driver/module") then
    nicmod = File.readlink("/sys/class/net/#{nic}/device/driver/module")
    if File.exists?("/sys/class/net/#{nic}/device/driver/module/version") then
      modver = %x!cat /sys/class/net/#{nic}/device/driver/module/version! 
    end
  elsif File.exists?("/sys/class/net/#{nic}/driver") then
    nicmod = File.readlink("/sys/class/net/#{nic}/driver")
    if File.exists?("/sys/class/net/#{nic}/driver/version") then
      modver = %x!cat /sys/class/net/#{nic}/driver/version!
    end
  end

  if nicmod then
    nicmod = (nicmod.split(/\//)[-1])
    nicmods << nicmod
    ethernet.store("#{nic}_driver", nicmod)
  else
    nicmods << ''
  end

  if modver then
    modver = modver.chomp
    modvers << modver.chomp
    ethernet.store("#{nic}_driver_version", modver)
  else
    modvers << ''
  end

  nicbusid = nil
  if File.exists?("/sys/class/net/#{nic}/device") then
    nicbusid = File.readlink("/sys/class/net/#{nic}/device")
  end
  if nicbusid then
    nicbusid = (nicbusid.split(/\//)[-1])
    nicbusids << nicbusid
    ethernet.store("#{nic}_busid", nicbusid)
  else
    nicbusids << ''
  end

  mac = nil
  if File.exists?("/sys/class/net/#{nic}/address") then
    mac = %x!cat /sys/class/net/#{nic}/address!
    mac = mac.chomp
    macs << mac.chomp
    ethernet.store("#{nic}_macaddress", mac)
  else
    macs << ''
  end

  ethtool_cmd = "ethtool -k #{nic} 2>/dev/null"

  IO.foreach("|#{ethtool_cmd}") { |line|
    line.chomp
    next if line.include? "Operation not supported"
    next if line.include? "Offload parameters for"
    next if line.include? "Features for"
    ethtool_data = line.split(':')
    key = "#{ethtool_data[0]}".chomp
    value = "#{ethtool_data[1]}".chomp
    clean_key(key)
    value = value.gsub(/\s+/, "")
    next if value.nil?
    ethernet.store("#{nic}_#{key}", value)
  }

  ethtool_cmd = "ethtool -i #{nic} 2>/dev/null"

  IO.foreach("|#{ethtool_cmd}") { |line|
    line.chomp
    ethtool_data = line.split(':')
    key = "#{ethtool_data[0]}".chomp
    value = "#{ethtool_data[1]}".chomp
    clean_key(key)
    value = value.gsub(/\s+/, "")
    next if value.nil?
    ethernet.store("#{nic}_#{key}", value)
  }

  IO.foreach("|/bin/cat /proc/interrupts | grep #{nic}") { |line|
    line.chomp
    nic_irq_num = line.split.first
    nic_irq_num = nic_irq_num.gsub(":", "")
    eth_irq = line.split.last
    if File.exists?("/proc/irq/#{nic_irq_num}/smp_affinity")
      irq_cpumask = %x!cat /proc/irq/#{nic_irq_num}/smp_affinity!
      irq_cpumask = irq_cpumask.chomp
    end
    ethernet.store("#{nic}_#{eth_irq}_irq_cpumask", irq_cpumask)
  }
}

ethernet.each do |key, value|
    add_fact(key, value)
end

