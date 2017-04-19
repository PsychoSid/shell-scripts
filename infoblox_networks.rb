#!/usr/bin/ruby

def call_infoblox(action, ref='network')
  require 'rest_client'
  require 'xmlsimple'
  require 'json'

  servername = '<SERVER>'
  username   = '<USER>'
  password   = '<PASSWORD>'
  url        = "https://#{servername}/wapi/v1.2/"+"#{ref}"

  params     = {
    :method=>action,
    :url=>url,
    :user=>username,
    :password=>password,
    :headers=>{ :content_type=>:xml, :accept=>:xml }
  }
  
  response = RestClient::Request.new(params).execute

  raise "Failure <- Infoblox Response:<#{response.code}>" unless response.code == 200 || response.code == 201

  response_hash = XmlSimple.xml_in(response)

  return response_hash
end

networks = call_infoblox(:get)

networks_hash = Hash[*networks['value'].collect { |x| [x['network'], x['_ref'][0]] }.flatten]
raise "networks_hash returned nil" if networks_hash.nil?

networks_hash.sort.each do |key, val|
  puts "Key: #{key}, Value: #{val}"
end
 
