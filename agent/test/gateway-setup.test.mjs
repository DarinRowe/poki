import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, writeFile, readFile, readdir, rm, chmod } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { makeMessages } from './fixtures/messages.mjs';

const run = promisify(execFile);
const root = resolve(import.meta.dirname, '../..');

async function cli(command, args, options = {}) {
  try { return { code: 0, ...await run(command, args, { cwd: root, ...options }) }; }
  catch (error) { return { code: error.code, stdout: error.stdout, stderr: error.stderr }; }
}

async function evidence(name, value) {
  if (!process.env.POKI_GATEWAY_EVIDENCE) return;
  await mkdir(process.env.POKI_GATEWAY_EVIDENCE, { recursive: true });
  await writeFile(join(process.env.POKI_GATEWAY_EVIDENCE, name), JSON.stringify(value, null, 2));
}

test('Optional gateway CLI skips downloads, cleans failures and preserves existing destinations', { skip: process.platform !== 'darwin' }, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'poki-gateway-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const commands = join(directory, 'commands');
  const temporary = join(directory, 'temporary');
  await mkdir(commands); await mkdir(temporary);
  const marker = join(directory, 'download-attempted');
  await writeFile(join(commands, 'curl'), '#!/bin/sh\ntouch "$POKI_DOWNLOAD_MARKER"\nexit 22\n', { mode: 0o755 });
  const env = { ...process.env, PATH: `${commands}:${process.env.PATH}`, TMPDIR: temporary, POKI_DOWNLOAD_MARKER: marker };
  const appDir = join(directory, 'Applications'), configDir = join(directory, 'config');
  const destinations = ['--app-dir', appDir, '--config-dir', configDir];
  const results = {};
  results.skip = await cli('./bin/setup-channels', ['--channel', 'none', ...destinations], { env });
  assert.equal(results.skip.code, 0);
  assert.match(results.skip.stdout, /Skipped iMessage/);
  await assert.rejects(readFile(marker), { code: 'ENOENT' });
  await assert.rejects(readdir(appDir), { code: 'ENOENT' });
  await assert.rejects(readdir(configDir), { code: 'ENOENT' });
  const secret = 'fixture-password-not-for-logs';
  const answers = join(directory, 'answers.json');
  await writeFile(answers, JSON.stringify({ url: 'http://127.0.0.1:1234', password: secret,
    sender: 'allowed@example.test', device: 'synthetic-device' }), { mode: 0o600 });
  const args = ['--channel', 'imessage', ...destinations, '--answers', answers];
  results.downloadFailure = await cli('./bin/setup-channels', args, { env });
  assert.equal(results.downloadFailure.code, 1);
  assert.match(results.downloadFailure.stderr, /Download failed/);
  await readFile(marker);
  const archive = join(directory, 'invalid.zip');
  await writeFile(archive, 'not the official release');
  results.checksumFailure = await cli('./bin/setup-channels', [...args, '--archive', archive], { env });
  assert.equal(results.checksumFailure.code, 1);
  assert.match(results.checksumFailure.stderr, /Checksum verification failed/);
  assert.deepEqual(await readdir(temporary), [], 'Failed downloads and checks leave no staging files');
  await assert.rejects(readdir(appDir), { code: 'ENOENT' });
  await assert.rejects(readdir(configDir), { code: 'ENOENT' });
  for (const [name, path] of [['existingApp', join(appDir, 'BlueBubbles.app')], ['existingConfig', configDir]]) {
    await mkdir(path, { recursive: true });
    await writeFile(join(path, 'keep'), 'existing user data');
    results[name] = await cli('./bin/setup-channels', args, { env });
    assert.equal(results[name].code, 1);
    assert.match(results[name].stderr, /already exists/);
    assert.equal(await readFile(join(path, 'keep'), 'utf8'), 'existing user data');
    await rm(path, { recursive: true });
  }
  assert.ok(!JSON.stringify(results).includes(secret));
  await evidence('installer-failure-and-skip.json', results);
});

test('Private-config launcher checks only the configured chat and does not disclose credentials', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'poki-gateway-launch-'));
  const api = await makeMessages();
  t.after(async () => { await api.close(); await rm(directory, { recursive: true, force: true }); });
  await writeFile(join(directory, 'imessage.json'), JSON.stringify({ sender: 'allowed@example.test',
    chatGuid: 'iMessage;-;allowed@example.test', device: 'synthetic-device', auth: 'chatgpt' }), { mode: 0o600 });
  const connection = join(directory, 'connection.json');
  await writeFile(connection, JSON.stringify({ url: api.url, password: api.password }), { mode: 0o600 });
  const args = ['bin/poki-imessage.mjs', '--config-dir', directory, '--check'];
  const result = await cli(process.execPath, args);
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /authentication and read check succeeded/);
  assert.deepEqual(api.requests.map(request => request.path), ['/api/v1/ping', '/api/v1/message/query']);
  const filters = api.requests[1].body.where;
  assert.ok(filters.some(filter => filter.args?.chatGuid === 'iMessage;-;allowed@example.test'));
  assert.equal(api.sent.length, 0);
  await assert.rejects(readFile(join(directory, 'state/messages.lock')), { code: 'ENOENT' });
  await chmod(connection, 0o644);
  const permissions = await cli(process.execPath, args);
  assert.equal(permissions.code, 1);
  await chmod(connection, 0o600);
  await writeFile(connection, '{invalid:' + api.password);
  const malformed = await cli(process.execPath, args);
  assert.equal(malformed.code, 1);
  assert.equal(api.requests.length, 2, 'Invalid credentials must not reach the gateway');
  assert.ok(!JSON.stringify([result, permissions, malformed]).includes(api.password));
  await evidence('private-launcher.json', { result, permissions, malformed, requests: api.requests, messagesSent: api.sent.length });
});
