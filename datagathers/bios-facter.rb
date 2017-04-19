require 'facter'

ENV["PATH"]="/bin:/sbin:/usr/bin:/usr/sbin:/root:/opt/hp/hp-scripting-tools/bin"

bios = Hash.new

def add_fact(fact, code)
    Facter.add(fact) { setcode { code } }
end
if (Facter.value("productname") =~ /.Gen./) then
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
        propertyName = feature_name.text.gsub(' ', '_')
      }

      feature.elements.each('option') { |option|
        next unless selectedOption == option.attributes["option_id"].to_i
        option.elements.each('option_name') { |on|
          validValues.push('' + on.text + '').to_s
        }
      }
      # bios.store(propertyName, validValues)
      add_fact("hpbios_#{propertyName}", validValues)
    }
  end
elsif File.executable?('/sbin/conrep') 
  system 'conrep -x /opt/hp/hp-scripting-tools/etc/conrep.xml -s -f /root/conrep-current.xml > /dev/null 2>&1'
  File.open('/root/conrep-current.xml').each do |line|
    line.chomp!
    next if !line.include? "Section name="
    keySplit = line.split(/\"(.*?)\"/)
    value = line.split(/\>(.*?)\</)
    unless value[1].nil? 
      add_fact("hpbios_#{keySplit[1]}", value[1])
    end
  end
end
