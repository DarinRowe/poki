import assert from 'node:assert/strict';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { once } from 'node:events';
import { watch } from 'node:fs';
import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { PokiClient } from '../poki-client.mjs';
import { MessageSource } from '../message-source.mjs';
import { makeMessages, addMessage } from '../test/fixtures/messages.mjs';

const exec = promisify(execFile);
const [device, destination, model, scenario = 'all'] = process.argv.slice(2);
assert.ok(device && destination && model, 'Usage: node agent/scripts/verify-agent.mjs <dedicated simulator UUID> <new output directory> <ChatGPT model> [all|prompt]');
assert.ok(['all', 'prompt'].includes(scenario), 'Choose all or prompt');
const root = resolve(import.meta.dirname, '../..');
const output = resolve(destination);
await mkdir(output, { recursive: true, mode: 0o700 });
assert.equal((await readdir(output)).length, 0, 'Use a new evidence directory');
const env = { ...process.env, POKI_MCP_STATE_DIR: join(output, 'mcp'), POKI_AGENT_AUTH: 'chatgpt' };
delete env.OPENAI_BASE_URL;
delete env.POKI_AGENT_SERVICE_TIER;
process.env.POKI_MCP_STATE_DIR = env.POKI_MCP_STATE_DIR;
const daemon = spawn(process.execPath, ['src/daemon.mjs', '--port', '0'], { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'] });
const daemonExit = once(daemon, 'exit');
let daemonLog = '';
daemon.stdout.on('data', chunk => { daemonLog += chunk; });
daemon.stderr.on('data', chunk => { daemonLog += chunk; });
const observer = new PokiClient();
let db, worker, recorder;
const parsed = result => {
  assert.ok(!result.isError, result.content.find(item => item.type === 'text')?.text);
  return JSON.parse(result.content.find(item => item.type === 'text').text);
};
const call = (name, args = {}) => observer.call(name, { device, ...args });
const observe = async () => parsed(await call('list_elements'));
async function waitForScreen(predicate, description) {
  const until = performance.now() + 30000;
  let screen;
  do { screen = await observe(); if (predicate(screen)) return screen; } while (performance.now() < until);
  await writeFile(join(output, 'prepare-failure.json'), JSON.stringify({ description, screen }, null, 2));
  assert.fail(description);
}
async function reset() {
  parsed(await call('launch_app', { bundle_id: 'local.pokimcp.fixture' }));
  assert.ok(parsed(await call('wait_for', { text: '重置测试状态', timeout_seconds: 30 })).matched);
  await call('hide_keyboard');
  parsed(await call('tap_text', { text: '重置测试状态' }));
  parsed(await call('launch_app', { bundle_id: 'local.pokimcp.fixture' }));
  return waitForScreen(screen => screen.foreground?.bundle_id === 'local.pokimcp.fixture' &&
    screen.elements.some(e => e.identifier === 'fixture-text' && e.value === '输入测试文字') &&
    screen.elements.some(e => e.label === '已保存：'), 'The fixture must be reset before a task');
}
async function snapshot(name) {
  const result = await call('observe_device', { source: 'accessibility' });
  const screen = parsed(result);
  await writeFile(join(output, `${name}.json`), JSON.stringify(screen, null, 2));
  const image = result.content.find(item => item.type === 'image');
  if (image) await writeFile(join(output, `${name}.png`), Buffer.from(image.data, 'base64'));
  return screen;
}
const stateDirectory = join(output, 'agent-state');
async function run(name, prompt, onReply) {
  const outbox = join(output, `${name}-replies.jsonl`);
  await writeFile(outbox, '');
  const before = new Set(await readdir(join(stateDirectory, 'tasks')).catch(() => []));
  db.outbox = outbox;
  addMessage(db, prompt);
  let transcript = '', seen = 0, handlerError;
  const replies = [];
  let handling = Promise.resolve();
  const watcher = watch(outbox, () => {
    handling = handling.then(async () => {
      const lines = (await readFile(outbox, 'utf8')).split('\n').filter(Boolean);
      for (const line of lines.slice(seen)) {
        const reply = JSON.parse(line);
        replies.push(reply.text);
        if (onReply) await onReply(reply.text);
      }
      seen = lines.length;
      if (onReply && (await readdir(join(stateDirectory, 'tasks')).catch(() => [])).some(file => !before.has(file))) worker?.kill('SIGTERM');
    }).catch(error => { handlerError = error; worker?.kill('SIGTERM'); });
  });
  worker = spawn(process.execPath, ['agent/imessage.mjs', '--config', join(output, 'config.json'), '--state', stateDirectory,
    ...(onReply ? [] : ['--once'])], { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'] });
  worker.stdout.on('data', chunk => { transcript += chunk; });
  worker.stderr.on('data', chunk => { transcript += chunk; });
  const timeout = setTimeout(() => { handlerError = new Error(`${name} exceeded 180 seconds`); worker?.kill('SIGTERM'); }, 180000);
  const [code, signal] = await once(worker, 'exit');
  clearTimeout(timeout); watcher.close(); await handling; worker = null;
  await writeFile(join(output, `${name}-terminal.txt`), transcript);
  if (handlerError) throw handlerError;
  assert.ok(code === 0 || onReply && signal === 'SIGTERM', `${transcript} Exit code=${code}, signal=${signal}`);
  const names = (await readdir(join(stateDirectory, 'tasks'))).filter(name => !before.has(name));
  assert.equal(names.length, 1, 'One incoming task must create exactly one task record');
  const result = JSON.parse(await readFile(join(stateDirectory, 'tasks', names[0]), 'utf8'));
  const screen = await snapshot(`${name}-final`);
  await writeFile(join(output, `${name}-result.json`), JSON.stringify({ result, replies, screen }, null, 2));
  console.log(JSON.stringify({ name, phase: result.phase, mode: result.execution.mode, learned: Boolean(result.execution.learned), modelResponses: result.metrics.modelResponses, result: result.result }));
  return { result, screen, replies };
}

try {
  await Promise.race([once(daemon.stdout, 'data'), daemonExit.then(() => { throw new Error('Isolated MCP failed to start'); })]);
  await observer.open('agent-acceptance-observer');
  const started = parsed(await observer.call('start_simulator', { simulator: device }));
  assert.equal(started.kind, 'simulator');
  await reset();
  db = await makeMessages();
  Object.assign(env, { BLUEBUBBLES_URL: db.url, BLUEBUBBLES_PASSWORD: db.password });
  Object.assign(process.env, { BLUEBUBBLES_URL: db.url, BLUEBUBBLES_PASSWORD: db.password });
  await new MessageSource({ sender: 'allowed@example.test', stateDirectory }).open();
  addMessage(db, 'Never execute this other sender message', { sender: 2 });
  addMessage(db, 'Never execute this group message', { chat: 3 });
  await writeFile(join(output, 'config.json'), JSON.stringify({ sender: 'allowed@example.test', device, model, auth: 'chatgpt' }), { mode: 0o600 });
  recorder = spawn('xcrun', ['simctl', 'io', device, 'recordVideo', join(output, 'messages-simulator.mp4')], { stdio: ['ignore', 'ignore', 'pipe'] });
  await once(recorder.stderr, 'data');
  const checks = {};
  if (scenario === 'all') {
    const prompt = text => `In Fernbrook (local.pokimcp.fixture), enter "${text}" in the test text field and verify the saved text. Do nothing else.`;
    const first = await run('first-message', prompt('Cedar'));
    assert.equal(first.result.phase, 'completed', first.result.result);
    assert.ok(first.screen.elements.some(e => e.label === '已保存：Cedar'));
    assert.ok(first.result.execution.learned, 'The first real task must learn a route');
    await reset();
    const repeat = await run('repeat-message', prompt('Birch'));
    assert.equal(repeat.result.phase, 'completed', repeat.result.result);
    assert.equal(repeat.result.execution.mode, 'route');
    assert.ok(!repeat.result.result.includes('Cedar'), 'A repeated task must not report the previous input in its result labels');
    assert.equal(repeat.result.metrics.modelResponses, 0, 'A learned route must use no model inference');
    assert.ok(repeat.screen.elements.some(e => e.label === '已保存：Birch'));
    Object.assign(checks, { firstMessage: true, learnedRoute: true, zeroModelRepeat: true });
  }
  const returned = await run('system-prompt', 'In Fernbrook (local.pokimcp.fixture), open the simulated sign-in, complete it with the app controls and verify the result.');
  assert.equal(returned.result.phase, 'completed', returned.result.result);
  assert.ok(returned.screen.elements.some(e => e.label === '已完成模拟登录'));
  await writeFile(join(output, 'acceptance.json'), JSON.stringify({ ...checks, systemPromptHandled: true,
    real: ['ChatGPT via pi', 'Poki MCP', 'dedicated simulator'], fake: ['BlueBubbles HTTP service', 'reply outbox', 'fictional sign-in app'], device }, null, 2));
} finally {
  if (worker) { worker.kill('SIGTERM'); await once(worker, 'exit').catch(() => {}); }
  if (recorder) { recorder.kill('SIGINT'); await once(recorder, 'exit').catch(() => {}); }
  await db?.close(); await observer.close();
  await exec('xcrun', ['simctl', 'shutdown', device]).catch(() => {});
  daemon.kill('SIGTERM'); await daemonExit;
  await writeFile(join(output, 'mcp.log'), daemonLog);
}
