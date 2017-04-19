require 'facter'

boottime = Hash.new

def add_fact(fact, code)
  Facter.add(fact) { setcode { code } }
end


IO.foreach("|/bin/cat /proc/cmdline") { |line|
  arguments = line.split
  arguments.each do |stuff|
    if stuff.include? "="
      arg_split = stuff.split("=")
      key = arg_split[0]
      value = arg_split[1]
      boottime.store(key, value)
    else
      key = stuff
      value = stuff
      boottime.store(key, value)
    end
  end
}

boottime.each do |key, value|
  add_fact("boot_param_#{key}", value)
end
