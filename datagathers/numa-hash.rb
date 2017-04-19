#!/usr/bin/env ruby

require 'pp'

sysfs_cpu_directory = '/sys/devices/system/cpu/'

cpus = []

numa = Hash.new

if File.exist?(sysfs_cpu_directory)
  Dir.entries(sysfs_cpu_directory).each do |cpu|
    sysfs_topology_directory = sysfs_cpu_directory + cpu + "/topology"
    next unless File.exist?(sysfs_topology_directory)

    coreid = sysfs_topology_directory + "/core_id"
    coresiblingslist = sysfs_topology_directory + "/core_siblings_list"
    physicalpackageid = sysfs_topology_directory + "/physical_package_id"
    threadsiblingslist = sysfs_topology_directory + "/thread_siblings_list"

    if File.exist?(coreid)
      numa.store("#{cpu}_coreid".to_sym, IO.read(coreid).strip.to_i)
    end

    if File.exist?(coresiblingslist)
      numa.store("#{cpu}_coresiblingslist".to_sym, IO.read(coresiblingslist).chomp)
    end

    if File.exist?(physicalpackageid)
      numa.store("#{cpu}_physicalpackageid".to_sym, IO.read(physicalpackageid).strip.to_i)
    end

    if File.exist?(threadsiblingslist)
      numa.store("#{cpu}_threadsiblingslist".to_sym, IO.read(threadsiblingslist).chomp)
    end
  end
end

sysfs_node_directory = '/sys/devices/system/node/'

numanodes = []

if File.exist?(sysfs_node_directory)
  # Iterate over each file in the /sys/devices/system/node/ directory and skip ones that do not have a cpulist file
  Dir.entries(sysfs_node_directory).each do |numadir|
    sysfs_numanodes_directory = sysfs_node_directory + numadir + "/cpulist"
    next unless File.exist?(sysfs_numanodes_directory)

    numanodes << numadir

    numacpulist = sysfs_numanodes_directory

    if File.exist?(numacpulist)
      numa.store("numa_#{numadir}_cpulist".to_sym, IO.read(numacpulist).chomp)
    end
  end
end

pp numa
exit
