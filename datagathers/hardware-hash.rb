#!/usr/bin/env ruby

require 'pp'

stage = 0
manufacturer = 'unknown'
product = 'unknown'
serialno = 'unknown'
biosdate = ''

hwdetails = Hash.new

ENV["PATH"]="/bin:/sbin:/usr/bin:/usr/sbin"
IO.foreach("|dmidecode") { |line|
  line = line.chomp
  stage = 0 if line =~ /^Handle/;
  if line =~ /^\s*BIOS Information/ then
    stage = 1
    next
  elsif line =~ /^\s*System Information/ then
    stage = 2
    next
  end
  if stage == 1 then
    if line =~ /^\s+Release Date:\s*(.*)\s*$/ then
    if $1 =~ /^(\d{2})\/(\d{2})\/(\d{4})$/ then
      biosdate = "#{$3}#{$1}#{$2}"
    end
    end
  elsif stage == 2 then
    manufacturer = $1 if line =~ /^\s+Manufacturer:\s*(.*)$/
    product = $1 if line =~ /^\s+Product Name:\s*(.*)$/
  end
}

manufacturer.sub!(/\s+$/, '')
product.sub!(/\s+$/, '')

hwdetails.store("manufacturer", manufacturer)
hwdetails.store("product", product)
hwdetails.store("biosdate", biosdate)

pp hwdetails

exit
