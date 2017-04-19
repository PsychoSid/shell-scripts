#!/usr/bin/env ruby
#
#
require 'pp'

@boottime = Hash.new

IO.foreach("|/bin/cat /proc/cmdline") { |line|
  arguments = line.split
  arguments.each do |stuff|
    if stuff.include? "="
      arg_split = stuff.split("=")
      key = arg_split[0]
      value = arg_split[1]
      @boottime.store(key, value)
    else
      key = stuff
      value = stuff
      @boottime.store(key, value)
    end
  end
}

pp @boottime
