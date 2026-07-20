import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';

const repoRoot = process.cwd().endsWith(`${path.sep}backend`)
  ? path.resolve(process.cwd(), '..')
  : process.cwd();

function readRepoFile(relativePath: string): string {
  return readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('TestFlight workflow keeps legacy OpenSSL P12 verification fallback', () => {
  const workflow = readRepoFile('.github/workflows/testflight.yml');

  assert.match(workflow, /openssl pkcs12 -in "\$RUNNER_TEMP\/cert\.p12" -noout -passin pass:"\$CERT_PWD"/);
  assert.match(workflow, /openssl pkcs12 -legacy -in "\$RUNNER_TEMP\/cert\.p12" -noout -passin pass:"\$CERT_PWD"/);
  assert.match(workflow, /openssl pkcs12 verification: OK \(legacy provider\)/);
});

test('TestFlight workflow installs the iOS platform before archiving when needed', () => {
  const workflow = readRepoFile('.github/workflows/testflight.yml');

  assert.match(workflow, /xcodebuild -showsdks \| grep -q -- '-sdk iphoneos'/);
  assert.match(workflow, /xcodebuild -downloadPlatform iOS/);
});

test('iOS workflows select the newest available Xcode 26 installation', () => {
  const testFlightWorkflow = readRepoFile('.github/workflows/testflight.yml');
  const screenshotsWorkflow = readRepoFile('.github/workflows/app-store-screenshots.yml');

  for (const workflow of [testFlightWorkflow, screenshotsWorkflow]) {
    assert.match(workflow, /Dir\.glob\('\/Applications\/Xcode\*\.app'\)/);
    assert.match(workflow, /version_key\(path\)/);
    assert.doesNotMatch(workflow, /\/Applications\/Xcode_26\.0\.app \/Applications\/Xcode_26\.1\.app/);
  }
});

test('TestFlight workflow uses a simulator runtime matching the selected Xcode SDK', () => {
  const workflow = readRepoFile('.github/workflows/testflight.yml');

  assert.match(workflow, /xcrun --sdk iphonesimulator --show-sdk-version/);
  assert.match(workflow, /SIMULATOR_SDK_VERSION/);
  assert.match(workflow, /matching = runtimes\.select/);
});

test('App Store screenshots workflow uses Ruby compatible with locked fastlane gems', () => {
  const workflow = readRepoFile('.github/workflows/app-store-screenshots.yml');

  assert.match(workflow, /ruby-version: "3\.1"/);
});

test('App Store screenshots workflow uploads to App Store Connect by default', () => {
  const workflow = readRepoFile('.github/workflows/app-store-screenshots.yml');

  assert.match(workflow, /upload_to_app_store:[\s\S]*default: "true"/);
  assert.match(workflow, /default: "iPhone 17 Pro Max,iPad Pro 13-inch \(M5\)"/);
  assert.match(workflow, /bundle exec fastlane ios upload_screenshots/);
  assert.match(workflow, /APP_STORE_CONNECT_KEY_ID/);
  assert.match(workflow, /APP_STORE_CONNECT_ISSUER_ID/);
  assert.match(workflow, /APP_STORE_CONNECT_API_KEY/);
});

test('App Store metadata workflow uploads editable metadata through fastlane', () => {
  const workflow = readRepoFile('.github/workflows/app-store-metadata.yml');
  const fastfile = readRepoFile('fastlane/Fastfile');

  assert.match(workflow, /bundle exec fastlane ios upload_metadata/);
  assert.match(workflow, /APP_STORE_CONNECT_KEY_ID/);
  assert.match(workflow, /APP_STORE_CONNECT_ISSUER_ID/);
  assert.match(workflow, /APP_STORE_CONNECT_API_KEY/);
  assert.match(fastfile, /lane :upload_metadata/);
  assert.match(fastfile, /metadata_path: METADATA_PATH/);
  assert.match(fastfile, /app_rating_config_path: APP_RATING_CONFIG_PATH/);
  assert.match(fastfile, /module ::Deliver/);
  assert.match(fastfile, /cubbylog_original_review_attachment_file/);
  assert.match(fastfile, /return unless options\[:app_review_attachment_file\]/);
  assert.match(fastfile, /skip_binary_upload: true/);
  assert.match(fastfile, /skip_screenshots: true/);
});

test('App Store subscription price workflow updates the yearly Pro product', () => {
  const workflow = readRepoFile('.github/workflows/app-store-subscription-price.yml');
  const priceScript = readRepoFile('fastlane/scripts/update_subscription_price.rb');
  const appStore = readRepoFile('backend/src/lib/appStore.ts');
  const subscriptionStore = readRepoFile('ios/StuffTracker/Stores/SubscriptionStore.swift');

  assert.match(workflow, /default: com\.jimgreco\.stufftracker\.pro\.yearly/);
  assert.match(workflow, /default: "9\.99"/);
  assert.match(workflow, /bundle exec ruby fastlane\/scripts\/update_subscription_price\.rb/);
  assert.match(workflow, /APP_STORE_CONNECT_KEY_ID/);
  assert.match(workflow, /APP_STORE_CONNECT_ISSUER_ID/);
  assert.match(workflow, /APP_STORE_CONNECT_API_KEY/);
  assert.match(priceScript, /SUBSCRIPTION_PRODUCT_ID/);
  assert.match(priceScript, /TARGET_CUSTOMER_PRICE/);
  assert.match(priceScript, /Base64\.urlsafe_decode64/);
  assert.match(priceScript, /\/v1\/subscriptions\/#\{subscription_id\}\/pricePoints/);
  assert.match(priceScript, /\/v1\/subscriptionPrices/);
  assert.match(appStore, /com\.jimgreco\.stufftracker\.pro\.monthly/);
  assert.match(appStore, /com\.jimgreco\.stufftracker\.pro\.yearly/);
  assert.match(subscriptionStore, /com\.jimgreco\.stufftracker\.pro\.monthly/);
  assert.match(subscriptionStore, /com\.jimgreco\.stufftracker\.pro\.yearly/);
});

test('App Store subscription review workflow completes and verifies both Pro products', () => {
  const workflow = readRepoFile('.github/workflows/app-store-subscription-review.yml');
  const reviewScript = readRepoFile('fastlane/scripts/configure_subscription_review.rb');
  const captureScript = readRepoFile('fastlane/scripts/capture_subscription_review_screenshot.sh');
  const reviewMetadata = JSON.parse(readRepoFile('fastlane/subscriptions/review_metadata.json'));
  const reviewScreenshot = readFileSync(
    path.join(repoRoot, 'fastlane/review_assets/subscription-review.png'),
  );
  const app = readRepoFile('ios/StuffTracker/StuffTrackerApp.swift');
  const account = readRepoFile('ios/StuffTracker/Views/Auth/AccountView.swift');

  assert.match(workflow, /bundle exec ruby fastlane\/scripts\/configure_subscription_review\.rb/);
  assert.match(workflow, /SUBSCRIPTION_PRODUCT_ID: com\.jimgreco\.stufftracker\.pro\.monthly/);
  assert.match(workflow, /TARGET_CUSTOMER_PRICE: "2\.99"/);
  assert.match(workflow, /VERIFY_ONLY: "true"/);
  assert.match(reviewScript, /\/v1\/subscriptionGroupLocalizations/);
  assert.match(reviewScript, /\/v1\/subscriptionLocalizations/);
  assert.match(reviewScript, /\/v1\/subscriptionAvailabilities/);
  assert.match(reviewScript, /\/v1\/subscriptionAppStoreReviewScreenshots/);
  assert.match(reviewScript, /sourceFileChecksum: Digest::MD5\.hexdigest\(bytes\)/);
  assert.match(captureScript, /--subscription-review-screenshot/);
  assert.match(app, /SubscriptionReviewScreenshotView/);
  assert.ok(account.includes('Text("Subscribe \\(plan.name)")'));
  assert.equal(reviewScreenshot.subarray(1, 4).toString(), 'PNG');
  assert.equal(reviewScreenshot.readUInt32BE(16), 1320);
  assert.equal(reviewScreenshot.readUInt32BE(20), 2868);
  assert.deepEqual(
    reviewMetadata.products.map((product: { productId: string }) => product.productId),
    [
      'com.jimgreco.stufftracker.pro.monthly',
      'com.jimgreco.stufftracker.pro.yearly',
    ],
  );
  for (const product of reviewMetadata.products) {
    assert.ok(product.displayName.length <= 30);
    assert.ok(product.description.length <= 45);
    assert.ok(account.includes(product.displayName));
    assert.ok(account.includes(product.description));
    assert.ok(account.includes(`price: "$${product.customerPrice}"`));
  }
});

test('App Store metadata copy stays within key App Store limits', () => {
  const subtitle = readRepoFile('fastlane/metadata/en-US/subtitle.txt').trim();
  const promotionalText = readRepoFile('fastlane/metadata/en-US/promotional_text.txt').trim();
  const keywords = readRepoFile('fastlane/metadata/en-US/keywords.txt').trim();
  const supportUrl = readRepoFile('fastlane/metadata/en-US/support_url.txt').trim();
  const privacyUrl = readRepoFile('fastlane/metadata/en-US/privacy_url.txt').trim();
  const primaryCategory = readRepoFile('fastlane/metadata/primary_category.txt').trim();
  const secondaryCategory = readRepoFile('fastlane/metadata/secondary_category.txt').trim();

  assert.equal(readRepoFile('fastlane/metadata/en-US/name.txt').trim(), 'CubbyLog');
  assert.ok(subtitle.length <= 30);
  assert.ok(promotionalText.length <= 170);
  assert.ok(keywords.length <= 100);
  assert.equal(supportUrl, 'https://cubbylog.com/support.html');
  assert.equal(privacyUrl, 'https://cubbylog.com/privacy.html');
  assert.equal(primaryCategory, 'PRODUCTIVITY');
  assert.equal(secondaryCategory, 'UTILITIES');
  assert.doesNotThrow(() => JSON.parse(readRepoFile('fastlane/metadata/app_rating_config.json')));
});

test('Fastlane frames App Store screenshots with marketing copy after capture', () => {
  const fastfile = readRepoFile('fastlane/Fastfile');
  const frameScript = readRepoFile('fastlane/scripts/frame_screenshots.swift');

  assert.match(fastfile, /SCREENSHOT_FRAME_SCRIPT/);
  assert.match(fastfile, /sh\("xcrun", "swift", SCREENSHOT_FRAME_SCRIPT, SCREENSHOT_OUTPUT_PATH\)/);
  assert.match(frameScript, /A map for\\nyour stuff/);
  assert.match(frameScript, /Keep essentials\\nclose/);
  assert.match(frameScript, /Search your\\nwhole home/);
  assert.match(frameScript, /Save the details\\nthat matter/);
});

test('Fastlane validates four framed screenshots for each generated device before upload', () => {
  const fastfile = readRepoFile('fastlane/Fastfile');
  const snapfile = readRepoFile('fastlane/Snapfile');

  assert.match(fastfile, /EXPECTED_SCREENSHOT_IDS = \[/);
  assert.match(fastfile, /validate_screenshot_upload_set/);
  assert.match(fastfile, /File\.join\(SCREENSHOT_OUTPUT_PATH, "\*\*", "\*.\{jpg,jpeg,png\}"\)/);
  assert.match(fastfile, /screenshots_by_device/);
  assert.match(fastfile, /TARGET_SCREENSHOT_DISPLAY_TYPES/);
  assert.match(fastfile, /screenshot_ids\.sort == EXPECTED_SCREENSHOT_IDS/);
  assert.match(fastfile, /iPad Pro 13-inch \(M5\)/);
  assert.match(snapfile, /iPhone 17 Pro Max,iPad Pro 13-inch \(M5\)/);
});

test('Fastlane uploads App Store screenshots once per target display type', () => {
  const fastfile = readRepoFile('fastlane/Fastfile');
  const uploadScreenshotsLane = fastfile.match(/lane :upload_screenshots do[\s\S]*?\n  end/)?.[0] ?? '';

  assert.doesNotMatch(uploadScreenshotsLane, /upload_to_app_store\(/);
  assert.match(fastfile, /replace_app_store_screenshot_set/);
  assert.match(fastfile, /set\.delete!/);
  assert.match(fastfile, /upload_screenshot\([\s\S]*wait_for_processing: true/);
  assert.match(fastfile, /reorder_screenshots\(app_screenshot_ids: uploaded_ids\)/);
});
