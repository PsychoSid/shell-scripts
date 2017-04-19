@cpu = Hash.new

$map2Valid = {}
def makeValid(invalid)
  if ! $map2Valid.has_key?(invalid)
   # Make into a valid name:
   # 1) Removing special characters
   # 2) Removing dots if it ends with dots + numbers
   #valid = invalid.downcase.gsub(/[- ()_\/:;,]/,'').sub(/^([0-9]+)/, 'i\1').sub(/\.([0-9]+)$/, '\1')
    valid = invalid.gsub(/[- ()_\/:;,]/,'').sub(/\.([0-9]+)$/, '\1')
    $map2Valid[invalid] = valid
  end
  $map2Valid[invalid]
end

def add_fact(fact, code)
  Facter.add(fact) { setcode { code } }
end

Dir.entries("/proc/acpi/processor").sort.each { |cpu|
  next if cpu == '.' || cpu == '..'
  next unless File.exists?("/proc/acpi/processor/#{cpu}/power")
  cpuid = cpu.downcase
  # Still a stupid old bug with ruby reading proc/sysfs so lets play safe...
  active_state = %x{ /bin/cat "/proc/acpi/processor/#{cpu}/power" | grep "active state:"}
  active_state = active_state.split
  add_fact("#{cpuid}_cstate", active_state[2])
}

if File.exists?("/usr/bin/lscpu") 
  IO.foreach("|/usr/bin/lscpu 2>/dev/null") { |line|
    line.chomp
    cpu_data = line.split(':')
    key = cpu_data[0].gsub(/\s+/, "")
    key = key.gsub(":", "")
    key = key.gsub(/[- ()\/;,]/,'')
    key = key.downcase
    value = cpu_data[1].gsub(/\s+/, "")
    value = value.downcase
    add_fact(key, value)
    if key == 'onlinecpuslist'
      key = 'lastcpuid'
      value = value.split('-').last
      add_fact(key, value)
    end
  }
end
