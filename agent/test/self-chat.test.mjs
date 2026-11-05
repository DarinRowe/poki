import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { makeMessages } from './fixtures/messages.mjs';

test('An idle self-chat supervisor exits on SIGTERM without calling device cleanup', { timeout: 15000 }, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'poki-idle-supervisor-'));
  const api = await makeMessages({ selfChat: true });
  const config = join(directory, 'config.json');
  const calls = join(directory, 'device-calls.txt');
  await writeFile(calls, '');
  await writeFile(config, JSON.stringify({ sender: 'allowed@example.test', chatGuid: 'any;-;allowed@example.test',
    device: 'synthetic-device', model: 'gpt-5.4', auth: 'api-key' }));
  const child = spawn(process.execPath, ['--import', './agent/test/fixtures/supervisor-no-device.mjs',
    'agent/scripts/self-chat.mjs', '--config', config, '--state', directory], { cwd: resolve(import.meta.dirname, '../..'),
    env: { ...process.env, IDEVICE_TOOLS: process.execPath, OPENAI_API_KEY: 'sk-local-idle-fixture', BLUEBUBBLES_URL: api.url,
      BLUEBUBBLES_PASSWORD: api.password, POKI_TEST_DEVICE_CALLS: calls }, stdio: ['ignore', 'pipe', 'pipe'] });
  const exited = once(child, 'exit');
  let transcript = '', stopped = false;
  const receive = data => {
    transcript += data;
    if (!stopped && transcript.includes('ready. Only new messages')) { stopped = true; child.kill('SIGTERM'); }
  };
  child.stdout.on('data', receive); child.stderr.on('data', receive);
  t.after(async () => {
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
    await exited; await api.close(); await rm(directory, { recursive: true, force: true });
  });
  const [code, signal] = await exited;
  assert.ok(stopped, transcript);
  assert.equal(await readFile(calls, 'utf8'), '', 'An idle worker must not trigger any device cleanup call');
  assert.equal(code, 0, `${signal}\n${transcript}`);
  assert.ok(!transcript.includes('Phone cleanup needs operator attention'));
  assert.ok(transcript.includes('Isolated MCP stopped.'));
  await assert.rejects(readFile(join(directory, 'mcp/mcp.json')), { code: 'ENOENT' });
  await assert.rejects(readFile(join(directory, 'worker/messages.lock')), { code: 'ENOENT' });
});

test('Self-chat refuses readiness when the physical device executable is missing', { timeout: 15000 }, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'poki-missing-device-tool-'));
  const config = join(directory, 'config.json');
  await writeFile(config, JSON.stringify({ device: 'synthetic-device', model: 'gpt-5.4', auth: 'api-key' }));
  const child = spawn(process.execPath, ['agent/scripts/self-chat.mjs', '--config', config, '--state', directory],
    { cwd: resolve(import.meta.dirname, '../..'), env: { ...process.env, IDEVICE_TOOLS: join(directory, 'absent-tool'),
      OPENAI_API_KEY: 'sk-local-preflight-fixture', BLUEBUBBLES_URL: 'http://127.0.0.1:1', BLUEBUBBLES_PASSWORD: 'unused' },
    stdio: ['ignore', 'pipe', 'pipe'] });
  let transcript = '';
  child.stdout.on('data', data => transcript += data); child.stderr.on('data', data => transcript += data);
  const exited = once(child, 'exit');
  t.after(async () => { if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM'); await exited; await rm(directory, { recursive: true, force: true }); });
  const [code] = await exited;
  assert.equal(code, 1);
  assert.match(transcript, /idevice-tools/);
  assert.match(transcript, /bin\/setup/);
  assert.ok(!transcript.includes('ready'), transcript);
});
