#!/usr/bin/env ruby

require "bigdecimal"
require "base64"
require "cgi"
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
  uri = if path_or_url.start_with?("http")
          URI(path_or_url)
        else
          URI("#{API_BASE_URL}#{path_or_url}")
        end
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
  response = paged_get("/v1/apps", query: { "filter[bundleId]" => bundle_id, "limit" => 1 })
  app = response["data"].first
  raise "Could not find App Store Connect app for bundle ID #{bundle_id}" unless app

  app["id"]
end

def subscriptions_for_app(app_id)
  groups = paged_get("/v1/apps/#{app_id}/subscriptionGroups", query: { "limit" => 200 })["data"]
  groups.flat_map do |group|
    paged_get(
      "/v1/subscriptionGroups/#{group["id"]}/subscriptions",
      query: {
        "fields[subscriptions]" => "name,productId,subscriptionPeriod",
        "limit" => 200
      }
    )["data"]
  end
end

def subscription_for_product_id(app_id, product_id)
  subscription = subscriptions_for_app(app_id).find do |candidate|
    candidate.dig("attributes", "productId") == product_id
  end
  raise "Could not find subscription product ID #{product_id}" unless subscription

  subscription
end

def subscription_review_details(subscription_id)
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
      "fields[subscriptionAppStoreReviewScreenshots]" => "fileName,assetDeliveryState"
    }
  )["data"]
  availability = request_json(
    "get",
    "/v1/subscriptions/#{subscription_id}/subscriptionAvailability",
    query: {
      "fields[subscriptionAvailabilities]" => "availableInNewTerritories"
    }
  )["data"]

  {
    subscription: subscription,
    localizations: localizations,
    screenshot: screenshot,
    availability: availability
  }
end

def print_subscription_review_audit(details)
  subscription = details.fetch(:subscription)
  attributes = subscription.fetch("attributes", {})
  localizations = details.fetch(:localizations)
  screenshot = details[:screenshot]
  availability = details[:availability]

  puts "Review state: #{attributes["state"] || "unknown"}"
  puts "Subscription period: #{attributes["subscriptionPeriod"] || "unknown"}"
  puts "Review note: #{attributes["reviewNote"].to_s.strip.empty? ? "missing" : "present"}"
  puts "Group level: #{attributes["groupLevel"] || "unset"}"
  puts "Family sharing: #{attributes["familySharable"] == true ? "enabled" : "disabled"}"
  if localizations.empty?
    puts "Localizations: missing"
  else
    localization_summary = localizations.map do |localization|
      localized = localization.fetch("attributes", {})
      "#{localized["locale"]}=#{localized["name"]} (#{localized["state"] || "unknown"})"
    end
    puts "Localizations: #{localization_summary.join(", ")}"
  end
  if screenshot
    screenshot_attributes = screenshot.fetch("attributes", {})
    delivery_state = screenshot_attributes.dig("assetDeliveryState", "state") || "unknown"
    puts "Review screenshot: #{screenshot_attributes["fileName"] || screenshot["id"]} (#{delivery_state})"
  else
    puts "Review screenshot: missing"
  end
  if availability
    available_in_new_territories = availability.dig("attributes", "availableInNewTerritories")
    puts "Availability: configured; new territories=#{available_in_new_territories == true ? "enabled" : "disabled"}"
  else
    puts "Availability: missing"
  end
end

def decimal(value)
  BigDecimal(value.to_s)
end

def price_matches?(actual, expected)
  decimal(actual) == decimal(expected)
rescue ArgumentError
  false
end

def subscription_price_points(subscription_id, territory)
  paged_get(
    "/v1/subscriptions/#{subscription_id}/pricePoints",
    query: {
      "filter[territory]" => territory,
      "fields[subscriptionPricePoints]" => "customerPrice,proceeds,proceedsYear2,territory,equalizations",
      "limit" => 200
    }
  )["data"]
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

def equalized_price_points(price_point_id)
  paged_get(
    "/v1/subscriptionPricePoints/#{CGI.escape(price_point_id)}/equalizations",
    query: {
      "fields[subscriptionPricePoints]" => "customerPrice,proceeds,proceedsYear2,territory",
      "limit" => 200
    }
  )["data"]
end

def current_price_point_ids(subscription_id)
  response = paged_get(
    "/v1/subscriptions/#{subscription_id}/prices",
    query: {
      "include" => "subscriptionPricePoint,territory",
      "fields[subscriptionPrices]" => "startDate,preserved,territory,subscriptionPricePoint",
      "fields[subscriptionPricePoints]" => "customerPrice,territory",
      "limit" => 200
    }
  )

  included_price_points = response["included"]
    .select { |resource| resource["type"] == "subscriptionPricePoints" }
    .to_h { |resource| [resource["id"], resource] }

  response["data"].each_with_object({}) do |price, prices_by_territory|
    next if price.dig("attributes", "preserved")

    price_point_id = price.dig("relationships", "subscriptionPricePoint", "data", "id")
    territory = price.dig("relationships", "territory", "data", "id") ||
      territory_for_price_point(included_price_points[price_point_id] || {})
    next unless territory && price_point_id

    prices_by_territory[territory] = price_point_id
  end
end

def create_subscription_price(subscription_id, price_point_id, preserve_current_price)
  request_json(
    "post",
    "/v1/subscriptionPrices",
    body: {
      data: {
        type: "subscriptionPrices",
        attributes: {
          preserveCurrentPrice: preserve_current_price
        },
        relationships: {
          subscription: {
            data: {
              type: "subscriptions",
              id: subscription_id
            }
          },
          subscriptionPricePoint: {
            data: {
              type: "subscriptionPricePoints",
              id: price_point_id
            }
          }
        }
      }
    }
  )
end

bundle_id = ENV.fetch("APP_IDENTIFIER", "com.jimgreco.stufftracker")
product_id = ENV.fetch("SUBSCRIPTION_PRODUCT_ID", "com.jimgreco.stufftracker.pro.yearly")
base_territory = ENV.fetch("BASE_TERRITORY", "USA")
target_price = ENV.fetch("TARGET_CUSTOMER_PRICE", "9.99")
preserve_current_price = bool_env("PRESERVE_CURRENT_PRICE", default: false)
dry_run = bool_env("DRY_RUN", default: false)

app_id = app_id_for_bundle(bundle_id)
subscription = subscription_for_product_id(app_id, product_id)
subscription_id = subscription["id"]
subscription_name = subscription.dig("attributes", "name") || product_id

puts "Found app #{bundle_id} (#{app_id})"
puts "Found subscription #{subscription_name} #{product_id} (#{subscription_id})"

review_details = subscription_review_details(subscription_id)
print_subscription_review_audit(review_details)

base_price_points = subscription_price_points(subscription_id, base_territory)
current_prices = current_price_point_ids(subscription_id)
current_base_price_point = base_price_points.find { |price_point| price_point["id"] == current_prices[base_territory] }
puts "Current #{base_territory} customer price: #{current_base_price_point&.dig("attributes", "customerPrice") || "missing"}"
target_price_point = base_price_points.find do |price_point|
  price_matches?(price_point.dig("attributes", "customerPrice"), target_price)
end

unless target_price_point
  nearby = base_price_points
    .sort_by { |price_point| (decimal(price_point.dig("attributes", "customerPrice")) - decimal(target_price)).abs }
    .first(10)
    .map { |price_point| "#{price_point.dig("attributes", "customerPrice")} (#{price_point["id"]})" }
  raise "Could not find #{base_territory} subscription price point #{target_price}. Nearby price points: #{nearby.join(", ")}"
end

equalizations = equalized_price_points(target_price_point["id"])
puts "No equalized price points returned; updating #{base_territory} only" if equalizations.empty?

target_price_points = ([target_price_point] + equalizations)
  .each_with_object({}) do |price_point, by_territory|
    territory = territory_for_price_point(price_point)
    by_territory[territory] = price_point if territory
  end

raise "No equalized price points found for #{target_price_point["id"]}" if target_price_points.empty?

price_points_to_apply = target_price_points.reject do |territory, price_point|
  current_prices[territory] == price_point["id"]
end

puts "Target #{base_territory} customer price: #{target_price_point.dig("attributes", "customerPrice")}"
puts "Target territories: #{target_price_points.length}"
puts "Already at target: #{target_price_points.length - price_points_to_apply.length}"
puts "Will update: #{price_points_to_apply.length}"

if dry_run
  puts "Dry run enabled; not updating App Store Connect"
  exit 0
end

price_points_to_apply.each_with_index do |(territory, price_point), index|
  puts "Updating #{territory} to #{price_point.dig("attributes", "customerPrice")} (#{index + 1}/#{price_points_to_apply.length})"
  create_subscription_price(subscription_id, price_point["id"], preserve_current_price)
  sleep 0.2
end

verified_prices = current_price_point_ids(subscription_id)
missing = target_price_points.reject do |territory, price_point|
  verified_prices[territory] == price_point["id"]
end

raise "Price update did not verify for territories: #{missing.keys.sort.join(", ")}" if missing.any?

puts "Updated #{product_id} to #{target_price_point.dig("attributes", "customerPrice")} in #{target_price_points.length} territories"
