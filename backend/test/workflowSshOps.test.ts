import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import path from 'node:path';

const repoRoot = process.cwd().endsWith(`${path.sep}backend`)
  ? path.resolve(process.cwd(), '..') : process.cwd();
const workflow = (name: string) => readFileSync(path.join(repoRoot, '.github/workflows', name), 'utf8');

// Execute the actual YAML run blocks, with local synthetic keys and command stubs.
function runBlock(name: string, step: string): string {
  const section = workflow(name).split(`      - name: ${step}\n`)[1]?.split('\n      - name: ')[0];
  assert.ok(section, `Missing ${step} in ${name}`);
  const body = section.split('        run: |\n')[1];
  assert.ok(body, `Missing run block for ${step}`);
  return body.split('\n').filter(line => line.startsWith('          '))
    .map(line => line.slice(10)).join('\n') + '\n';
}

function executable(dir: string, name: string, body: string) {
  writeFileSync(path.join(dir, name), `#!/bin/bash\nset -euo pipefail\n${body}\n`, { mode: 0o700 });
}

for (const [name, step] of [
  ['ops-checks.yml', 'Prepare SSH'],
  ['production-restore-drill.yml', 'Prepare SSH'],
  ['production-db-hardening.yml', 'Prepare SSH'],
  ['deploy.yml', 'Transfer stuff app to EC2'],
]) {
  test(`${name} parses synthetic keys with or without a final newline and rejects invalid keys`, () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'workflow-key-'));
    try {
      const bin = path.join(dir, 'bin');
      mkdirSync(bin);
      executable(bin, 'rsync', 'echo rsync >> "$TEST_CALLS"');
      const script = runBlock(name, step);
      assert.doesNotMatch(script, /\$\{\{ secrets\./);
      for (const type of ['ed25519', 'rsa']) {
        const keyPath = path.join(dir, `synthetic-${type}`);
        const generated = spawnSync('ssh-keygen', ['-q', '-t', type, '-N', '', '-f', keyPath], { encoding: 'utf8' });
        assert.equal(generated.status, 0, 'Synthetic key generation failed');
        const key = readFileSync(keyPath, 'utf8');
        for (const secret of [key.trimEnd(), key]) {
          const result = spawnSync('bash', ['-c', script], {
            cwd: dir, encoding: 'utf8',
            env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, TEST_CALLS: path.join(dir, 'calls'),
              EC2_SSH_KEY: secret, EC2_SSH_KNOWN_HOSTS: 'synthetic-host-entry', EC2_HOST: 'test.invalid', EC2_USER: 'test' },
          });
          assert.equal(result.status, 0, 'Synthetic key should parse');
          assert.equal(result.stdout, '', 'Private/public key material must not be logged');
          assert.equal(result.stderr, '', 'Valid key preparation should be silent');
          assert.equal(readFileSync(path.join(dir, 'key.pem')).at(-1), 10);
          assert.equal(statSync(path.join(dir, 'key.pem')).mode & 0o777, 0o600);
        }
      }
      for (const secret of ['', 'not-a-key', '$(touch injected)']) {
        writeFileSync(path.join(dir, 'calls'), '');
        const result = spawnSync('bash', ['-c', script], {
          cwd: dir, encoding: 'utf8',
          env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, TEST_CALLS: path.join(dir, 'calls'),
            EC2_SSH_KEY: secret, EC2_SSH_KNOWN_HOSTS: 'synthetic-host-entry', EC2_HOST: 'test.invalid', EC2_USER: 'test' },
        });
        assert.notEqual(result.status, 0, 'Invalid key must stop the step before connecting');
        assert.equal(readFileSync(path.join(dir, 'calls'), 'utf8'), '');
        assert.equal(result.stdout, '');
        assert.throws(() => statSync(path.join(dir, 'injected')));
      }
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
}

function simulateOps(checkOnly: string, options: { fail?: string; stale?: boolean; remoteMode?: string; noBackup?: boolean } = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), 'workflow-ops-'));
  try {
    const bin = path.join(dir, 'bin');
    const deploy = path.join(dir, 'deploy');
    const backups = path.join(deploy, 'backups');
    mkdirSync(bin);
    mkdirSync(backups, { recursive: true });
    const backup = path.join(backups, 'stuff-tracker-synthetic.sql.gz');
    writeFileSync(backup, 'synthetic backup - never deleted');
    writeFileSync(path.join(deploy, '.env'), `STUFF_DB_BACKUP_DIR='${backups}'\nDB_BACKUP_MAX_AGE_HOURS=26\n`);
    const calls = path.join(dir, 'calls');
    writeFileSync(calls, '');
    executable(bin, 'ssh', `
      echo ssh >> "$TEST_CALLS"
      command="\${!#}"
      case "$command" in
        'bash -se -- true') mode=true ;;
        'bash -se -- false') mode=false ;;
        *) exit 91 ;;
      esac
      exec bash -se -- "\${TEST_REMOTE_MODE:-$mode}"
    `);
    // Mock GNU find/stat so the exact remote shell can also be tested on macOS.
    executable(bin, 'find', `
      echo find >> "$TEST_CALLS"
      if [ "$TEST_NO_BACKUP" != true ]; then printf '2000000000 %s\\n' "$TEST_BACKUP"; fi
    `);
    executable(bin, 'stat', 'printf "%s\\n" "$TEST_BACKUP_EPOCH"');
    executable(bin, 'date', 'echo 2000000000');
    executable(bin, 'docker-compose', `
      printf '%s\\n' "$*" >> "$TEST_CALLS"
      cat > /dev/null
      case "$*" in *"$TEST_FAIL"*) exit 42 ;; esac
    `);
    const script = runBlock('ops-checks.yml', 'Run production operations checks')
      .replace('cd ~/deploy', 'cd "$TEST_DEPLOY_DIR"');
    const result = spawnSync('bash', ['-c', script], {
      cwd: dir, encoding: 'utf8', env: {
        ...process.env, PATH: `${bin}:${process.env.PATH}`, CHECK_ONLY: checkOnly,
        EC2_USER: 'test', EC2_HOST: 'test.invalid', TEST_CALLS: calls,
        TEST_DEPLOY_DIR: deploy, TEST_BACKUP: backup,
        TEST_BACKUP_EPOCH: options.stale ? '1000000000' : '2000000000',
        TEST_FAIL: options.fail || 'never-match-a-command', TEST_REMOTE_MODE: options.remoteMode || '',
        STUFF_DB_APP_ROLE: 'stuff_app',
        TEST_NO_BACKUP: String(options.noBackup || false),
      },
    });
    assert.equal(readFileSync(backup, 'utf8'), 'synthetic backup - never deleted');
    return { ...result, calls: readFileSync(calls, 'utf8') };
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

test('manual ops defaults to check-only; only scheduled or explicitly opted-in runs can clean up', () => {
  const source = workflow('ops-checks.yml');
  assert.match(source, /check_only:\n\s+description:[^\n]+\n\s+type: boolean\n\s+default: true/);
  assert.match(source, /CHECK_ONLY: \$\{\{ github\.event_name == 'workflow_dispatch' && inputs\.check_only \}\}/);
  const checked = simulateOps('true');
  assert.equal(checked.status, 0, checked.stderr);
  assert.deepEqual(checked.calls.trim().split('\n'), [
    'ssh', 'find',
    'exec -T stuff npm run storage:s3:check',
    'exec -T -e DB_EXPECTED_APP_ROLE=stuff_app stuff npm run db:hardening:check',
  ]);
  assert.match(checked.stdout, /Newest backup is fresh/);
  assert.match(checked.stdout, /Deletion disabled: skipping storage:cleanup:deleted-homes and activity:cleanup/);
  assert.match(checked.stdout, /Production operations checks completed \(check_only=true\)/);

  const cleanup = simulateOps('false');
  assert.equal(cleanup.status, 0, cleanup.stderr);
  assert.match(cleanup.calls, /storage:cleanup:deleted-homes/);
  assert.match(cleanup.calls, /activity:cleanup/);
});

test('each failed hardening check fails ops, still runs the other check, and prevents all cleanup', () => {
  for (const mode of ['true', 'false']) {
    for (const fail of ['storage:s3:check', 'db:hardening:check']) {
      const result = simulateOps(mode, { fail });
      assert.equal(result.status, 1);
      assert.match(result.calls, /storage:s3:check/);
      assert.match(result.calls, /db:hardening:check/);
      assert.doesNotMatch(result.calls, /storage:cleanup|activity:cleanup/);
      assert.match(result.stdout, /One or more hardening checks failed; cleanup will not run/);
    }
  }
});

test('stale or missing backups fail ops before any container or deletion commands', () => {
  for (const mode of ['true', 'false']) {
    for (const options of [{ stale: true }, { noBackup: true }]) {
      const result = simulateOps(mode, options);
      assert.equal(result.status, 1);
      assert.doesNotMatch(result.calls, /npm run/);
    }
  }
});

test('invalid check-only input stops locally or remotely before operations', () => {
  for (const mode of ['', 'TRUE', 'yes', 'false; exit 0']) {
    const local = simulateOps(mode);
    assert.equal(local.status, 1);
    assert.equal(local.calls, '');
    if (mode) {
      const remote = simulateOps('true', { remoteMode: mode });
      assert.equal(remote.status, 1);
      assert.equal(remote.calls, 'ssh\n');
    }
  }
});
