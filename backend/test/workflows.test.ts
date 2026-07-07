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

test('App Store metadata copy stays within key App Store limits', () => {
  const subtitle = readRepoFile('fastlane/metadata/en-US/subtitle.txt').trim();
  const promotionalText = readRepoFile('fastlane/metadata/en-US/promotional_text.txt').trim();
  const keywords = readRepoFile('fastlane/metadata/en-US/keywords.txt').trim();
  const supportUrl = readRepoFile('fastlane/metadata/en-US/support_url.txt').trim();
  const privacyUrl = readRepoFile('fastlane/metadata/en-US/privacy_url.txt').trim();

  assert.equal(readRepoFile('fastlane/metadata/en-US/name.txt').trim(), 'CubbyLog');
  assert.ok(subtitle.length <= 30);
  assert.ok(promotionalText.length <= 170);
  assert.ok(keywords.length <= 100);
  assert.equal(supportUrl, 'https://cubbylog.com/support.html');
  assert.equal(privacyUrl, 'https://cubbylog.com/privacy.html');
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
