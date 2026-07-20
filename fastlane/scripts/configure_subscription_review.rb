#!/usr/bin/env ruby

require "base64"
require "digest"
require "json"
require "net/http"
require "spaceship/connect_api/token"
require "uri"

API_BASE_URL = "https://api.appstoreconnect.apple.com"

def required_env(name)
  value = ENV[name].to_s.strip
  raise "#{name} is required" if value.empty?

  value
end

def bool_env(name, default: false)
  value = ENV[name]
  return default if value.nil? || value.strip.empty?

  %w[1 true yes on].include?(value.strip.downcase)
end

def auth_token
  @auth_token ||= Spaceship::ConnectAPI::Token.create(
    key_id: required_env("APP_STORE_CONNECT_KEY_ID"),
    issuer_id: required_env("APP_STORE_CONNECT_ISSUER_ID"),
    key: required_env("APP_STORE_CONNECT_API_KEY"),
    duration: 1200,
    in_house: false
  ).text
end

def api_url(path_or_url, query = nil)
  uri = path_or_url.start_with?("http") ? URI(path_or_url) : URI("#{API_BASE_URL}#{path_or_url}")
  uri.query = URI.encode_www_form(query) if query && !query.empty?
  uri
end

def request_json(method, path_or_url, query: nil, body: nil)
  uri = api_url(path_or_url, query)
  request_class = Net::HTTP.const_get(method.capitalize)
  request = request_class.new(uri)
  request["Authorization"] = "Bearer #{auth_token}"
  request["Content-Type"] = "application/json"
  request["Accept"] = "application/json"
  request.body = JSON.generate(body) if body

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
    http.request(request)
  end
  parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
  return parsed if response.is_a?(Net::HTTPSuccess)

  errors = parsed["errors"] || []
  detail = errors.map { |error| [error["code"], error["title"], error["detail"]].compact.join(": ") }.join("; ")
  raise "#{method.upcase} #{uri} failed with #{response.code}: #{detail.empty? ? response.body : detail}"
end

def request_json_optional(method, path_or_url, query: nil)
  request_json(method, path_or_url, query: query)
rescue RuntimeError => error
  return { "data" => nil } if error.message.include?(" failed with 404:")

  raise
end

def paged_get(path, query: nil)
  results = []
  included = []
  next_url = path
  next_query = query

  loop do
    page = request_json("get", next_url, query: next_query)
    results.concat(Array(page["data"]))
    included.concat(Array(page["included"]))
    next_url = page.dig("links", "next")
    next_query = nil
    break if next_url.nil? || next_url.empty?
  end

  { "data" => results, "included" => included }
end

def app_id_for_bundle(bundle_id)
  app = paged_get("/v1/apps", query: { "filter[bundleId]" => bundle_id, "limit" => 1 })["data"].first
  raise "Could not find App Store Connect app for bundle ID #{bundle_id}" unless app

  app["id"]
end

def subscription_group_and_products(app_id, product_ids)
  groups = paged_get(
    "/v1/apps/#{app_id}/subscriptionGroups",
    query: { "fields[subscriptionGroups]" => "referenceName", "limit" => 200 }
  )["data"]

  products_by_id = {}
  product_group_ids = {}
  groups.each do |group|
    subscriptions = paged_get(
      "/v1/subscriptionGroups/#{group["id"]}/subscriptions",
      query: {
        "fields[subscriptions]" => "name,productId,state,subscriptionPeriod,reviewNote,groupLevel,familySharable",
        "limit" => 200
      }
    )["data"]
    subscriptions.each do |subscription|
      product_id = subscription.dig("attributes", "productId")
      next unless product_ids.include?(product_id)

      products_by_id[product_id] = subscription
      product_group_ids[product_id] = group["id"]
    end
  end

  missing = product_ids - products_by_id.keys
  raise "Could not find subscriptions: #{missing.join(", ")}" if missing.any?

  group_ids = product_group_ids.values.uniq
  raise "Subscriptions are not in the same group: #{product_group_ids}" unless group_ids.length == 1

  group = groups.find { |candidate| candidate["id"] == group_ids.first }
  [group, products_by_id]
end

def group_localizations(group_id)
  paged_get(
    "/v1/subscriptionGroups/#{group_id}/subscriptionGroupLocalizations",
    query: {
      "fields[subscriptionGroupLocalizations]" => "name,customAppName,locale,state",
      "limit" => 200
    }
  )["data"]
end

def subscription_details(subscription_id)
  subscription = request_json(
    "get",
    "/v1/subscriptions/#{subscription_id}",
    query: {
      "fields[subscriptions]" => "name,productId,state,subscriptionPeriod,reviewNote,groupLevel,familySharable"
    }
  )["data"]
  localizations = paged_get(
    "/v1/subscriptions/#{subscription_id}/subscriptionLocalizations",
    query: {
      "fields[subscriptionLocalizations]" => "name,description,locale,state",
      "limit" => 200
    }
  )["data"]
  screenshot = request_json(
    "get",
    "/v1/subscriptions/#{subscription_id}/appStoreReviewScreenshot",
    query: {
      "fields[subscriptionAppStoreReviewScreenshots]" => "fileSize,fileName,sourceFileChecksum,imageAsset,assetDeliveryState"
    }
  )["data"]
  availability = request_json_optional(
    "get",
    "/v1/subscriptions/#{subscription_id}/subscriptionAvailability",
    query: {
      "fields[subscriptionAvailabilities]" => "availableInNewTerritories,availableTerritories"
    }
  )["data"]
  available_territories = if availability
                            paged_get(
                              "/v1/subscriptionAvailabilities/#{availability["id"]}/availableTerritories",
                              query: { "limit" => 200 }
                            )["data"]
                          else
                            []
                          end

  {
    subscription: subscription,
    localizations: localizations,
    screenshot: screenshot,
    availability: availability,
    available_territories: available_territories
  }
end

def territory_for_price_point(price_point)
  related_territory = price_point.dig("relationships", "territory", "data", "id")
  return related_territory if related_territory

  encoded_id = price_point["id"].to_s
  decoded = Base64.urlsafe_decode64(encoded_id + ("=" * ((4 - encoded_id.length % 4) % 4)))
  JSON.parse(decoded)["t"]
rescue ArgumentError, JSON::ParserError
  nil
end

def current_customer_price(subscription_id, territory)
  response = paged_get(
    "/v1/subscriptions/#{subscription_id}/prices",
    query: {
      "include" => "subscriptionPricePoint,territory",
      "fields[subscriptionPrices]" => "startDate,preserved,territory,subscriptionPricePoint",
      "fields[subscriptionPricePoints]" => "customerPrice,territory",
      "limit" => 200
    }
  )
  price_points = response["included"]
    .select { |resource| resource["type"] == "subscriptionPricePoints" }
    .to_h { |resource| [resource["id"], resource] }

  response["data"].each do |price|
    next if price.dig("attributes", "preserved")

    price_point_id = price.dig("relationships", "subscriptionPricePoint", "data", "id")
    price_point = price_points[price_point_id]
    price_territory = price.dig("relationships", "territory", "data", "id") || territory_for_price_point(price_point || {})
    return price_point.dig("attributes", "customerPrice") if price_territory == territory && price_point
  end

  nil
end

def patch_subscription(subscription_id, attributes)
  request_json(
    "patch",
    "/v1/subscriptions/#{subscription_id}",
    body: {
      data: {
        type: "subscriptions",
        id: subscription_id,
        attributes: attributes
      }
    }
  )
end

def create_group_localization(group_id, locale, name)
  request_json(
    "post",
    "/v1/subscriptionGroupLocalizations",
    body: {
      data: {
        type: "subscriptionGroupLocalizations",
        attributes: { locale: locale, name: name },
        relationships: {
          subscriptionGroup: {
            data: { type: "subscriptionGroups", id: group_id }
          }
        }
      }
    }
  )
end

def patch_group_localization(localization_id, name)
  request_json(
    "patch",
    "/v1/subscriptionGroupLocalizations/#{localization_id}",
    body: {
      data: {
        type: "subscriptionGroupLocalizations",
        id: localization_id,
        attributes: { name: name }
      }
    }
  )
end

def create_subscription_localization(subscription_id, locale, name, description)
  request_json(
    "post",
    "/v1/subscriptionLocalizations",
    body: {
      data: {
        type: "subscriptionLocalizations",
        attributes: {
          locale: locale,
          name: name,
          description: description
        },
        relationships: {
          subscription: {
            data: { type: "subscriptions", id: subscription_id }
          }
        }
      }
    }
  )
end

def patch_subscription_localization(localization_id, name, description)
  request_json(
    "patch",
    "/v1/subscriptionLocalizations/#{localization_id}",
    body: {
      data: {
        type: "subscriptionLocalizations",
        id: localization_id,
        attributes: { name: name, description: description }
      }
    }
  )
end

def set_subscription_availability(subscription_id, territory_ids)
  request_json(
    "post",
    "/v1/subscriptionAvailabilities",
    body: {
      data: {
        type: "subscriptionAvailabilities",
        attributes: { availableInNewTerritories: true },
        relationships: {
          availableTerritories: {
            data: territory_ids.map { |id| { type: "territories", id: id } }
          },
          subscription: {
            data: { type: "subscriptions", id: subscription_id }
          }
        }
      }
    }
  )
end

def upload_operation(operation, bytes)
  uri = URI(operation.fetch("url"))
  request_class = Net::HTTP.const_get(operation.fetch("method").capitalize)
  request = request_class.new(uri)
  Array(operation["requestHeaders"]).each do |header|
    request[header.fetch("name")] = header.fetch("value")
  end

  offset = Integer(operation.fetch("offset", 0))
  length = Integer(operation.fetch("length", bytes.bytesize))
  request.body = bytes.byteslice(offset, length)
  raise "Upload operation requested bytes outside the screenshot" unless request.body&.bytesize == length

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
    http.request(request)
  end
  return if response.is_a?(Net::HTTPSuccess)

  raise "Screenshot upload failed with #{response.code}: #{response.body}"
end

def reserve_and_upload_screenshot(subscription_id, screenshot_path)
  bytes = File.binread(screenshot_path)
  raise "Screenshot is empty: #{screenshot_path}" if bytes.empty?

  reservation = request_json(
    "post",
    "/v1/subscriptionAppStoreReviewScreenshots",
    body: {
      data: {
        type: "subscriptionAppStoreReviewScreenshots",
        attributes: {
          fileName: File.basename(screenshot_path),
          fileSize: bytes.bytesize
        },
        relationships: {
          subscription: {
            data: { type: "subscriptions", id: subscription_id }
          }
        }
      }
    }
  )["data"]

  screenshot_id = reservation.fetch("id")
  operations = reservation.dig("attributes", "uploadOperations") || []
  raise "App Store Connect did not return screenshot upload operations" if operations.empty?

  operations.each { |operation| upload_operation(operation, bytes) }

  request_json(
    "patch",
    "/v1/subscriptionAppStoreReviewScreenshots/#{screenshot_id}",
    body: {
      data: {
        type: "subscriptionAppStoreReviewScreenshots",
        id: screenshot_id,
        attributes: {
          uploaded: true,
          sourceFileChecksum: Digest::MD5.hexdigest(bytes)
        }
      }
    }
  )

  wait_for_screenshot(screenshot_id)
end

def wait_for_screenshot(screenshot_id, attempts: 30)
  attempts.times do
    screenshot = request_json(
      "get",
      "/v1/subscriptionAppStoreReviewScreenshots/#{screenshot_id}",
      query: {
        "fields[subscriptionAppStoreReviewScreenshots]" => "fileName,sourceFileChecksum,imageAsset,assetDeliveryState"
      }
    )["data"]
    state = screenshot.dig("attributes", "assetDeliveryState", "state")
    return screenshot if state == "COMPLETE"

    errors = screenshot.dig("attributes", "assetDeliveryState", "errors")
    raise "Screenshot processing failed: #{errors}" if %w[FAILED ERROR].include?(state)

    sleep 4
  end

  raise "Timed out waiting for subscription review screenshot #{screenshot_id}"
end

def validate_config(config)
  raise "bundleId is required" if config["bundleId"].to_s.empty?
  raise "locale is required" if config["locale"].to_s.empty?
  raise "groupDisplayName is required" if config["groupDisplayName"].to_s.empty?
  raise "reviewNote is required" if config["reviewNote"].to_s.empty?
  raise "reviewNote exceeds 4000 characters" if config["reviewNote"].length > 4000

  products = Array(config["products"])
  raise "Exactly two subscription products are required" unless products.length == 2
  products.each do |product|
    %w[productId period displayName description baseTerritory customerPrice].each do |key|
      raise "#{key} is required for a subscription product" if product[key].to_s.empty?
    end
    raise "#{product["productId"]} displayName exceeds 30 characters" if product["displayName"].length > 30
    raise "#{product["productId"]} description exceeds 45 characters" if product["description"].length > 45
  end
end

def ensure_group_localization(group_id, config, apply:)
  locale = config.fetch("locale")
  desired_name = config.fetch("groupDisplayName")
  localization = group_localizations(group_id).find { |item| item.dig("attributes", "locale") == locale }

  if localization.nil?
    puts "Group localization #{locale}: missing -> #{desired_name}"
    create_group_localization(group_id, locale, desired_name) if apply
  elsif localization.dig("attributes", "name") != desired_name
    puts "Group localization #{locale}: updating -> #{desired_name}"
    patch_group_localization(localization["id"], desired_name) if apply
  else
    puts "Group localization #{locale}: configured"
  end
end

def configure_subscription(subscription, product, config, territory_ids, screenshot_path, apply:)
  subscription_id = subscription.fetch("id")
  product_id = product.fetch("productId")
  details = subscription_details(subscription_id)
  attributes = details.fetch(:subscription).fetch("attributes")

  puts "\n#{product_id} (#{subscription_id})"
  puts "State: #{attributes["state"]}"
  raise "#{product_id} has period #{attributes["subscriptionPeriod"]}, expected #{product["period"]}" unless attributes["subscriptionPeriod"] == product["period"]

  desired_subscription_attributes = {
    reviewNote: config.fetch("reviewNote"),
    groupLevel: Integer(product.fetch("groupLevel"))
  }
  needs_subscription_patch = attributes["reviewNote"] != desired_subscription_attributes[:reviewNote] ||
    attributes["groupLevel"] != desired_subscription_attributes[:groupLevel]
  if needs_subscription_patch
    puts "Review note/group level: updating"
    patch_subscription(subscription_id, desired_subscription_attributes) if apply
  else
    puts "Review note/group level: configured"
  end

  locale = config.fetch("locale")
  localization = details.fetch(:localizations).find { |item| item.dig("attributes", "locale") == locale }
  if localization.nil?
    puts "Localization #{locale}: missing -> #{product["displayName"]}"
    create_subscription_localization(
      subscription_id,
      locale,
      product.fetch("displayName"),
      product.fetch("description")
    ) if apply
  elsif localization.dig("attributes", "name") != product["displayName"] ||
        localization.dig("attributes", "description") != product["description"]
    puts "Localization #{locale}: updating -> #{product["displayName"]}"
    patch_subscription_localization(
      localization["id"],
      product.fetch("displayName"),
      product.fetch("description")
    ) if apply
  else
    puts "Localization #{locale}: configured"
  end

  availability = details[:availability]
  available_ids = details.fetch(:available_territories).map { |territory| territory["id"] }.sort
  if availability.nil?
    puts "Availability: missing -> all #{territory_ids.length} territories"
    set_subscription_availability(subscription_id, territory_ids) if apply
  elsif available_ids != territory_ids.sort || availability.dig("attributes", "availableInNewTerritories") != true
    puts "Availability: #{available_ids.length}/#{territory_ids.length} territories; requires all territories"
    raise "Existing availability requires a manual correction for #{product_id}" if apply
  else
    puts "Availability: all #{territory_ids.length} territories"
  end

  screenshot = details[:screenshot]
  if screenshot.nil?
    puts "Review screenshot: missing -> #{File.basename(screenshot_path)}"
    reserve_and_upload_screenshot(subscription_id, screenshot_path) if apply
  else
    state = screenshot.dig("attributes", "assetDeliveryState", "state")
    puts "Review screenshot: #{screenshot.dig("attributes", "fileName")} (#{state})"
    wait_for_screenshot(screenshot["id"]) if apply && state != "COMPLETE"
  end
end

def verify_subscription(subscription, product, config, territory_ids)
  subscription_id = subscription.fetch("id")
  product_id = product.fetch("productId")
  details = subscription_details(subscription_id)
  attributes = details.fetch(:subscription).fetch("attributes")
  failures = []

  failures << "period is #{attributes["subscriptionPeriod"]}" unless attributes["subscriptionPeriod"] == product["period"]
  failures << "review note is missing or stale" unless attributes["reviewNote"] == config["reviewNote"]
  failures << "group level is #{attributes["groupLevel"]}" unless attributes["groupLevel"] == Integer(product["groupLevel"])

  localization = details.fetch(:localizations).find { |item| item.dig("attributes", "locale") == config["locale"] }
  if localization.nil?
    failures << "#{config["locale"]} localization is missing"
  else
    failures << "display name is stale" unless localization.dig("attributes", "name") == product["displayName"]
    failures << "description is stale" unless localization.dig("attributes", "description") == product["description"]
  end

  screenshot_state = details.dig(:screenshot, "attributes", "assetDeliveryState", "state")
  failures << "review screenshot is #{screenshot_state || "missing"}" unless screenshot_state == "COMPLETE"

  available_ids = details.fetch(:available_territories).map { |territory| territory["id"] }.sort
  failures << "availability covers #{available_ids.length}/#{territory_ids.length} territories" unless available_ids == territory_ids.sort
  failures << "new territories are disabled" unless details.dig(:availability, "attributes", "availableInNewTerritories") == true

  actual_price = current_customer_price(subscription_id, product.fetch("baseTerritory"))
  failures << "#{product["baseTerritory"]} price is #{actual_price || "missing"}" unless actual_price == product["customerPrice"]

  raise "#{product_id} is not review-ready: #{failures.join("; ")}" if failures.any?

  puts "#{product_id}: metadata, screenshot, availability, and #{product["baseTerritory"]} price verified (state #{attributes["state"]})"
end

config_path = File.expand_path(ENV.fetch("SUBSCRIPTION_REVIEW_CONFIG", "fastlane/subscriptions/review_metadata.json"))
screenshot_path = File.expand_path(ENV.fetch("SUBSCRIPTION_REVIEW_SCREENSHOT", "fastlane/review_assets/subscription-review.png"))
config = JSON.parse(File.read(config_path))
validate_config(config)

apply = bool_env("APPLY", default: false)
verify_only = bool_env("VERIFY_ONLY", default: false)
raise "APPLY and VERIFY_ONLY cannot both be true" if apply && verify_only
raise "Screenshot not found: #{screenshot_path}" unless File.file?(screenshot_path)

product_ids = config.fetch("products").map { |product| product.fetch("productId") }
app_id = app_id_for_bundle(config.fetch("bundleId"))
group, subscriptions = subscription_group_and_products(app_id, product_ids)
territory_ids = paged_get("/v1/territories", query: { "limit" => 200 })["data"].map { |territory| territory["id"] }.sort
raise "App Store Connect returned no territories" if territory_ids.empty?

puts "Found app #{config["bundleId"]} (#{app_id})"
puts "Found subscription group #{group.dig("attributes", "referenceName")} (#{group["id"]})"
puts "Mode: #{verify_only ? "verify" : apply ? "apply" : "dry run"}"

if verify_only
  group_localization = group_localizations(group["id"]).find do |item|
    item.dig("attributes", "locale") == config["locale"]
  end
  unless group_localization&.dig("attributes", "name") == config["groupDisplayName"]
    raise "Subscription group #{config["locale"]} localization is missing or stale"
  end

  config.fetch("products").each do |product|
    verify_subscription(subscriptions.fetch(product.fetch("productId")), product, config, territory_ids)
  end
  puts "Both subscriptions are ready to attach to the app-version review submission"
else
  ensure_group_localization(group["id"], config, apply: apply)
  config.fetch("products").each do |product|
    configure_subscription(
      subscriptions.fetch(product.fetch("productId")),
      product,
      config,
      territory_ids,
      screenshot_path,
      apply: apply
    )
  end
  puts apply ? "Applied subscription review metadata" : "Dry run complete; App Store Connect was not changed"
end
