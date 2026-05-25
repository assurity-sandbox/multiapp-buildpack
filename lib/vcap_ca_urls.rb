#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "set"

vcap_services = ENV.fetch("VCAP_SERVICES", "")
exit 0 if vcap_services.strip.empty?

begin
  services = JSON.parse(vcap_services)
rescue JSON::ParserError => e
  warn "Invalid VCAP_SERVICES JSON: #{e.message}"
  exit 1
end

unless services.is_a?(Hash)
  warn "Invalid VCAP_SERVICES JSON: expected a JSON object"
  exit 1
end

def aurora_postgres_binding?(binding)
  label = binding["label"].to_s
  name = binding["name"].to_s
  tags = Array(binding["tags"]).map { |tag| tag.to_s.downcase }

  label == "csb-aws-aurora-postgresql" ||
    name == "csb-aws-aurora-postgresql" ||
    (tags.include?("aurora") && (tags.include?("postgres") || tags.include?("postgresql")))
end

urls = Set[]

services.each_value do |bindings|
  Array(bindings).each do |binding|
    next unless binding.is_a?(Hash)
    next unless aurora_postgres_binding?(binding)

    credentials = binding["credentials"]
    next unless credentials.is_a?(Hash)

    url = credentials["certificate_authority_url"].to_s.strip
    urls.add(url) unless url.empty?
  end
end

puts urls.to_a
