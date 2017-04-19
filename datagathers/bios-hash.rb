#!/usr/bin/ruby
# Won't need this function outside of testing output
require 'pp'

ENV["PATH"]="/bin:/sbin:/usr/bin:/usr/sbin:/root"

bios = Hash.new

if File.executable?('/sbin/hp-rcu')

  require 'rexml/document'

  system 'hp-rcu -a -s -f /root/hp-rcu.xml > /dev/null 2>&1'

  hprcuXml = REXML::Document.new(File.open("/root/hp-rcu.xml"))

  root = hprcuXml.root

  hprcuXml.root.elements.each('/hprcu/feature') { |feature|
    next unless feature.attributes['feature_type'] == 'option'
    propertyName = ''
    validValues = []

    selectedOption = feature.attributes["selected_option_id"].to_i

    feature.elements.each('feature_name') { |feature_name|
      propertyName = feature_name.text
    }

    feature.elements.each('option') { |option|
      next unless selectedOption == option.attributes["option_id"].to_i
      option.elements.each('option_name') { |on|
        validValues.push('' + on.text + '')
      }
    }
    bios.store(propertyName, validValues)
  }
  pp bios
  exit
end

if File.executable?('/root/conrep')
  system '/root/conrep -x /root/conrep.xml -s -f /root/conrep-current.xml > /dev/null 2>&1'
  File.open('/root/conrep-current.xml').each do |line|
    line.chomp!
    next if !line.include? "Section name="
    keySplit = line.split(/\"(.*?)\"/)
    value = line.split(/\>(.*?)\</)
    unless value[1].nil? 
      bios.store(keySplit[1], value[1])
    end
  end
  pp bios
end
