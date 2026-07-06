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
  assert.match(fastfile, /screenshots_path: SCREENSHOT_OUTPUT_PATH/);
  assert.match(fastfile, /File\.join\(SCREENSHOT_OUTPUT_PATH, "\*\*", "\*.\{jpg,jpeg,png\}"\)/);
  assert.match(fastfile, /screenshots_by_device/);
  assert.match(fastfile, /screenshot_ids\.sort == EXPECTED_SCREENSHOT_IDS/);
  assert.match(fastfile, /iPad Pro 13-inch \(M5\)/);
  assert.match(snapfile, /iPhone 17 Pro Max,iPad Pro 13-inch \(M5\)/);
});
