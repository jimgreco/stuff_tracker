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
