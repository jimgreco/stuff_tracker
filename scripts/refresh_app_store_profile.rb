#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"
require "fileutils"

API_BASE = "https://api.appstoreconnect.apple.com/v1"

def require_env(name)
  value = ENV[name].to_s
  abort "Missing #{name}" if value.empty?
  value
end

def b64url(value)
  Base64.urlsafe_encode64(value).delete("=")
end

def jwt_signature(key, signing_input)
  digest = OpenSSL::Digest::SHA256.digest(signing_input)
  der = key.dsa_sign_asn1(digest)
  sequence = OpenSSL::ASN1.decode(der)
  r = sequence.value[0].value.to_s(2).rjust(32, "\0")[-32, 32]
  s = sequence.value[1].value.to_s(2).rjust(32, "\0")[-32, 32]
  r + s
end

def app_store_token(key_id:, issuer_id:, key_path:)
  key = OpenSSL::PKey.read(File.read(key_path))
  header = { alg: "ES256", kid: key_id, typ: "JWT" }
  payload = {
    iss: issuer_id,
    exp: Time.now.to_i + (20 * 60),
    aud: "appstoreconnect-v1"
  }
  signing_input = [b64url(JSON.generate(header)), b64url(JSON.generate(payload))].join(".")
  [signing_input, b64url(jwt_signature(key, signing_input))].join(".")
end

def request(method, path, token, query: nil, body: nil, allowed: nil)
  uri = URI("#{API_BASE}#{path}")
  uri.query = URI.encode_www_form(query) if query

  request_class = Net::HTTP.const_get(method.capitalize)
  http_request = request_class.new(uri)
  http_request["Authorization"] = "Bearer #{token}"
  http_request["Content-Type"] = "application/json"
  http_request.body = JSON.generate(body) if body

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(http_request)
  end

  expected = allowed || case method
                        when "get" then ["200"]
                        when "post" then ["201"]
                        when "delete" then ["204"]
                        else ["200"]
                        end
  return nil if expected.include?(response.code) && response.body.to_s.empty?
  return JSON.parse(response.body) if expected.include?(response.code)

  warn "App Store Connect #{method.upcase} #{uri} failed with HTTP #{response.code}"
  warn response.body
  exit 1
end

def first_data(response, description)
  data = response.fetch("data")
  abort "No #{description} found" if data.empty?
  data.first
end

def profile_matches_bundle?(profile, bundle_id)
  profile.dig("relationships", "bundleId", "data", "id") == bundle_id
end

key_id = require_env("KEY_ID")
issuer_id = require_env("ISSUER_ID")
api_key_path = require_env("API_KEY_PATH")
bundle_identifier = ENV.fetch("IOS_BUNDLE_ID", "com.jimgreco.stufftracker")
profile_name = ENV.fetch("IOS_PROFILE_NAME", "Stuff Tacker App Store")
profile_type = ENV.fetch("IOS_PROFILE_TYPE", "IOS_APP_STORE")
capability_type = ENV.fetch("IOS_CAPABILITY_TYPE", "ASSOCIATED_DOMAINS")
profile_dir = ENV.fetch(
  "IOS_PROFILE_DIR",
  File.join(Dir.home, "Library", "MobileDevice", "Provisioning Profiles")
)

token = app_store_token(key_id: key_id, issuer_id: issuer_id, key_path: api_key_path)

bundle = first_data(
  request(
    "get",
    "/bundleIds",
    token,
    query: {
      "filter[identifier]" => bundle_identifier,
      "fields[bundleIds]" => "identifier,name,platform",
      "limit" => "1"
    }
  ),
  "bundle ID #{bundle_identifier}"
)
bundle_id = bundle.fetch("id")
puts "Bundle ID: #{bundle_identifier} (#{bundle_id})"

capabilities = request(
  "get",
  "/bundleIds/#{bundle_id}/bundleIdCapabilities",
  token,
  query: {
    "fields[bundleIdCapabilities]" => "capabilityType",
    "limit" => "200"
  }
).fetch("data")

if capabilities.any? { |capability| capability.dig("attributes", "capabilityType") == capability_type }
  puts "Capability already enabled: #{capability_type}"
else
  request(
    "post",
    "/bundleIdCapabilities",
    token,
    body: {
      data: {
        type: "bundleIdCapabilities",
        attributes: { capabilityType: capability_type },
        relationships: {
          bundleId: {
            data: { type: "bundleIds", id: bundle_id }
          }
        }
      }
    }
  )
  puts "Enabled capability: #{capability_type}"
end

profiles_response = request(
  "get",
  "/profiles",
  token,
  query: {
    "filter[name]" => profile_name,
    "filter[profileType]" => profile_type,
    "include" => "bundleId,certificates",
    "fields[profiles]" => "name,profileType,profileState,profileContent,uuid,bundleId,certificates",
    "limit" => "200"
  }
)

profiles = profiles_response.fetch("data").select { |profile| profile_matches_bundle?(profile, bundle_id) }
certificate_ids = profiles.flat_map do |profile|
  profile.dig("relationships", "certificates", "data").to_a.map { |certificate| certificate.fetch("id") }
end.uniq

if certificate_ids.empty?
  certificates = request(
    "get",
    "/certificates",
    token,
    query: {
      "filter[certificateType]" => "IOS_DISTRIBUTION",
      "fields[certificates]" => "certificateType,displayName,expirationDate,serialNumber,activated",
      "limit" => "200"
    }
  ).fetch("data")

  certificate_ids = certificates
                    .select { |certificate| certificate.dig("attributes", "activated") != false }
                    .select { |certificate| Time.parse(certificate.dig("attributes", "expirationDate")) > Time.now }
                    .map { |certificate| certificate.fetch("id") }
end

abort "No active iOS distribution certificates found for #{profile_name}" if certificate_ids.empty?
puts "Using #{certificate_ids.length} distribution certificate(s)"

profiles.each do |profile|
  puts "Deleting provisioning profile: #{profile.dig("attributes", "name")} (#{profile.fetch("id")})"
  request("delete", "/profiles/#{profile.fetch("id")}", token)
end

created = request(
  "post",
  "/profiles",
  token,
  body: {
    data: {
      type: "profiles",
      attributes: {
        name: profile_name,
        profileType: profile_type
      },
      relationships: {
        bundleId: {
          data: { type: "bundleIds", id: bundle_id }
        },
        certificates: {
          data: certificate_ids.map { |certificate_id| { type: "certificates", id: certificate_id } }
        }
      }
    }
  }
).fetch("data")

profile = request(
  "get",
  "/profiles/#{created.fetch("id")}",
  token,
  query: {
    "fields[profiles]" => "name,profileType,profileState,profileContent,uuid"
  }
).fetch("data")

content = profile.dig("attributes", "profileContent")
uuid = profile.dig("attributes", "uuid")
abort "Created profile did not include profileContent" if content.to_s.empty?
abort "Created profile did not include uuid" if uuid.to_s.empty?

FileUtils.mkdir_p(profile_dir)
profile_path = File.join(profile_dir, "#{uuid}.mobileprovision")
File.binwrite(profile_path, Base64.decode64(content))

puts "Installed provisioning profile: #{profile_path}"
