#!/usr/bin/env ruby

require 'pp'
require 'timeout'

@solarflare = Hash.new

def clean_item(item)
  item.gsub!(" ", "_")
  item.gsub!(".", "_")
  item.downcase!
  item.sub(/eth./) {|match| return "sfc_#{match.scan(/eth.*/).last}"}
  item
end

def path(h, f_path = [] )
  cohort = get_siblings(h)
  cohort.each do |key|
    if h[key].kind_of?(Hash)
      h[key].each do |k,v|
        if v.kind_of?(Hash)
          f_path.push(key)
          path(h[key], f_path)
          f_path.pop
        elsif v.kind_of?(String)
          terminal_path = f_path.dup
          terminal_path << key unless terminal_path.include?(key)
          terminal_path << k unless terminal_path.include?(k)
          terminal_path.collect! { |item| clean_item(item.dup)}
          terminal_path = terminal_path.join('_')
          unless terminal_path.include? "this_utility_contains"
            @solarflare.store(terminal_path, v)
          end
        end
      end
    end
  end
end

def get_siblings(h)
  siblings = []
  h = h.reject{|k,v| !v.kind_of?(Hash)}
  h.each_key {|k| siblings << k }
  siblings.sort
  return siblings
end

begin
  if File.directory?("/sys/bus/pci/drivers/sfc")
    tstatus = Timeout::timeout(15) {
      if File.exists?("/usr/sbin/sfupdate")
        p = %x{/usr/sbin/sfupdate}
        p_array, p_hash = [], {}
        @sfc_array = []
        p.each{|line| p_array << [line.chomp.lstrip, line =~ /\S/] unless line.match(/^\s+$/)}

        hash_stack = [p_hash]
        (0..p_array.length).each do |i|
          if i < p_array.length-1
            new_key = p_array[i][0].split(/:/).first
            new_value = p_array[i][0].split(/:/).last.squeeze(" ").strip

            if p_array[i][0] =~ /eth[0-9] .*$/
              @sfc_array << p_array[i][0].split(/\s/).last
            end

            if p_array[i+1][1] > p_array[i][1]
              hash_new = {}
              hash_stack[-1][p_array[i][0]] = hash_new
              hash_stack.push hash_new
            elsif p_array[i+1][1] < p_array[i][1]
              hash_stack[-1][new_key] = new_value
              hash_stack.pop
            elsif p_array[i+1][1] == p_array[i][1]
              hash_stack[-1][new_key] = new_value
            end
          elsif i == p_array.length-1
            hash_stack[-1][new_key] = new_value
          end
        end

        hash_stack = hash_stack.first
        path(hash_stack)
      end
    }
    pp @solarflare
  end
  rescue Timeout::Error
    ""
end
