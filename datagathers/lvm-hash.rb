#!/usr/bin/env ruby

require 'pp'

lvm = Hash.new

vg_list = []

vgs_cmd = %x{vgs -o name --noheadings 2>/dev/null}.chomp

if !vgs_cmd.nil?
  vg_list = vgs_cmd.split
  lvm.store("number_of_volume_groups",  vg_list.length)
end

vg_list.each_with_index do |vg, i|
  lvm.store("volume_group_#{i}", vg)
end

pv_list = []

pvs_cmd = %x{pvs -o name --noheadings 2>/dev/null}.chomp

if !pvs_cmd.nil?
  pv_list = pvs_cmd.split
  lvm.store("number_of_physical_volumes", pv_list.length)
end

pv_list.each_with_index do |pv, i|
  lvm.store("physical_volume_#{i}", pv)
end

pp lvm

exit
