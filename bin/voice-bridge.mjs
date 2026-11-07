#!/usr/bin/env node
// Poki voice bridge: hands the Poki app short-lived OpenAI Realtime credentials, so the phone never
// holds the API key, and runs the voice tools that move the phone through the local Poki MCP.
//
//   OPENAI_API_KEY=... POKI_MCP_STATE_DIR=... node bin/voice-bridge.mjs [--port 47830] [--host 0.0.0.0] [--device <id>]
//
// The phone opens http://<this Mac>:<port>/voice/<secret>/ ; the secret is in voice-bridge.json in the
// state directory. Endpoints under that prefix:
//   GET  token   a client secret for one Realtime session (expires in 60 s), plus the session it opens
//   POST tool    {call_id, name, arguments}: runs one voice tool once; the same call_id never runs twice
//   GET  ledger  the calls this bridge ran, newest last, so a reconnecting phone can say what already happened
// With --test-dir <dir> (test runs of the app, poki://voice?test=1-20):
//   GET  utterance?n=01  recorded speech <dir>/u01.24k.pcm (24 kHz mono PCM16)
//   POST report          one finished test turn, appended to voice-test-report.jsonl in the state directory
import http from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { appendFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { networkInterfaces } from 'node:os';
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';
import { root, stateDir } from '../src/config.mjs';

const arg = (name, fallback) => { const i = process.argv.indexOf(`--${name}`); return i < 0 ? fallback : process.argv[i + 1]; };
const port = Number(arg('port', '47830'));
const host = arg('host', '0.0.0.0');
const device = arg('device', process.env.POKI_VOICE_DEVICE);
const testDir = arg('test-dir');
const apiKey = process.env.OPENAI_API_KEY;
if (!apiKey) { console.error('Set OPENAI_API_KEY (for example from the keychain) before starting the voice bridge.'); process.exit(1); }

const model = process.env.POKI_VOICE_MODEL ?? 'gpt-realtime-2.1';
const instructions = `You are Poki, a voice assistant that operates the user's iPhone with tools.
Speak briefly: one short sentence per reply, in the user's language.
When a tool can answer or do what the user asks, call it at once, without speaking first. Never guess facts about the phone; use a tool.
Call a tool once per request. Never repeat an action that already ran, including actions from before a reconnect that the conversation says have finished.
If the user tells you to stop or be quiet, stop talking, but anything already running keeps running; when its result arrives, report it in one sentence.
To read a page, open it first, then read the screen.`;

// The voice tools. `local` tools are answered by the phone itself; the bridge runs the others through Poki MCP.
const voiceTools = [
  { name: 'get_ios_version', local: true, description: 'Read the iPhone model and its iOS version. Changes nothing on the phone.', parameters: { type: 'object', properties: {}, additionalProperties: false } },
  { name: 'open_settings', description: 'Open a page of the Settings app on the iPhone, for example about, general, software_update, battery, wifi, display.', parameters: { type: 'object', properties: { page: { type: 'string', enum: ['about', 'general', 'software_update', 'battery', 'wifi', 'bluetooth', 'display', 'sounds', 'notifications', 'privacy', 'screen_time'] } }, required: ['page'], additionalProperties: false } },
  { name: 'read_screen', description: 'Read the text and controls on the iPhone screen now.', parameters: { type: 'object', properties: {}, additionalProperties: false } },
  { name: 'open_app', description: 'Open an app on the iPhone by its name, for example Calculator, Clock, Weather.', parameters: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'], additionalProperties: false } },
  { name: 'tap_text', description: 'Tap the visible button or row whose text matches.', parameters: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'], additionalProperties: false } },
  { name: 'go_home', description: 'Go to the Home Screen.', parameters: { type: 'object', properties: {}, additionalProperties: false } },
];

function sessionConfig({ effort = 'low', vad = 'server_vad', voice = 'marin' } = {}) {
  const turn = vad === 'semantic_vad'
    ? { type: 'semantic_vad', eagerness: 'high', create_response: true, interrupt_response: true }
    : { type: 'server_vad', silence_duration_ms: 450, prefix_padding_ms: 300, threshold: 0.5, create_response: true, interrupt_response: true };
  return {
    type: 'realtime',
    model,
    instructions,
    output_modalities: ['audio'],
    audio: {
      input: { turn_detection: turn, noise_reduction: { type: 'near_field' }, transcription: { model: 'gpt-4o-mini-transcribe' } },
      output: { voice },
    },
    tools: voiceTools.map(({ name, description, parameters }) => ({ type: 'function', name, description, parameters })),
    tool_choice: 'auto',
    parallel_tool_calls: false,
    reasoning: { effort },
  };
}

const text = result => result.content.filter(c => c.type === 'text').map(c => c.text).join('\n');
const clip = (s, n = 1800) => s.length > n ? `${s.slice(0, n)}…` : s;

// Voice tool → Poki MCP call. Each returns the string the model reads.
const runners = {
  async get_ios_version(mcp) {
    const info = JSON.parse(text(await mcp.call('get_device_info', {})));
    return JSON.stringify({ model: info.model, ios_version: info.osVersion });
  },
  open_settings: async (mcp, a) => clip(text(await mcp.call('open_settings', { page: a.page }))),
  read_screen: async mcp => clip(text(await mcp.call('list_elements', { max_elements: 60 }))),
  open_app: async (mcp, a) => clip(text(await mcp.call('launch_app', { name: a.name }))),
  tap_text: async (mcp, a) => clip(text(await mcp.call('tap_text', { text: a.text }))),
  go_home: async mcp => clip(text(await mcp.call('press_button', { button: 'home' }))),
};

class Mcp {
  async connect() {
    this.client = new Client({ name: 'poki-voice-bridge', version: '0.1.0' });
    await this.client.connect(new StdioClientTransport({ command: process.execPath, args: [join(root, 'src/stdio.mjs')], env: { ...process.env, POKI_MCP_SESSION: 'voice-bridge' } }));
  }
  async call(name, args) {
    const result = await this.client.callTool({ name, arguments: device ? { device, ...args } : args }, { timeout: 60000 });
    if (result.isError) throw new Error(clip(text(result), 600));
    return result;
  }
}

async function bridgeSecret() {
  const file = join(stateDir, 'voice-bridge.json');
  const saved = await readFile(file, 'utf8').then(JSON.parse).catch(() => null);
  if (saved?.secret) return { secret: saved.secret, file };
  const secret = randomBytes(24).toString('base64url');
  await mkdir(stateDir, { recursive: true, mode: 0o700 });
  await writeFile(file, JSON.stringify({ secret }) + '\n', { mode: 0o600 });
  return { secret, file };
}

const ledgerFile = join(stateDir, 'voice-ledger.jsonl');
const ledger = new Map();   // call_id → { entry, done: Promise }

async function runTool(mcp, { call_id, name, arguments: args = {} }) {
  const seen = ledger.get(call_id);
  if (seen) { await seen.done; return { ...seen.entry, replayed: true }; }
  const entry = { call_id, name, args, state: 'running', started: Date.now() };
  const done = (async () => {
    const runner = runners[name];
    try {
      if (!runner) throw new Error(`unknown voice tool ${name}`);
      entry.output = await runner(mcp, args);
      entry.state = 'done';
    } catch (error) {
      entry.output = `error: ${error.message}`;
      entry.state = 'failed';
    }
    entry.finished = Date.now();
    await appendFile(ledgerFile, JSON.stringify({ call_id, name, args, state: entry.state, started: entry.started, finished: entry.finished, output: clip(entry.output, 300) }) + '\n', { mode: 0o600 });
  })();
  ledger.set(call_id, { entry, done });
  await done;
  return entry;
}

async function mintToken(options) {
  const session = sessionConfig(options);
  const response = await fetch('https://api.openai.com/v1/realtime/client_secrets', {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ expires_after: { anchor: 'created_at', seconds: 60 }, session }),
  });
  const body = await response.json();
  // OpenAI echoes a masked key in some errors; keep even that out of logs and replies.
  const reason = (body.error?.message ?? `client_secrets ${response.status}`).replace(/sk-[\w*-]+/g, 'the API key');
  if (!response.ok) throw Object.assign(new Error(reason), { status: response.status });
  return { value: body.value, expires_at: body.expires_at, model, local_tools: voiceTools.filter(t => t.local).map(t => t.name) };
}

const readBody = req => new Promise((resolve, reject) => {
  let data = '';
  req.setEncoding('utf8');
  req.on('data', chunk => { data += chunk; if (data.length > 65536) reject(new Error('body too large')); });
  req.on('end', () => resolve(data));
  req.on('error', reject);
});

const { secret, file } = await bridgeSecret();
const mcp = new Mcp();
await mcp.connect();

const server = http.createServer(async (req, res) => {
  const reply = (status, body) => { res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' }); res.end(JSON.stringify(body)); };
  const url = new URL(req.url, 'http://bridge');
  const [, scope, given, action] = url.pathname.split('/');
  const ok = scope === 'voice' && given && given.length === secret.length && timingSafeEqual(Buffer.from(given), Buffer.from(secret));
  if (!ok) return reply(404, { error: 'not found' });
  try {
    if (req.method === 'GET' && action === 'token') {
      const options = Object.fromEntries(['effort', 'vad', 'voice'].map(k => [k, url.searchParams.get(k) ?? undefined]).filter(([, v]) => v));
      const started = Date.now();
      const token = await mintToken(options);
      console.log(JSON.stringify({ event: 'token', ms: Date.now() - started, options }));
      return reply(200, token);
    }
    if (req.method === 'POST' && action === 'tool') {
      const call = JSON.parse(await readBody(req));
      if (typeof call.call_id !== 'string' || typeof call.name !== 'string') return reply(400, { error: 'call_id and name are required' });
      const entry = await runTool(mcp, call);
      console.log(JSON.stringify({ event: 'tool', call_id: call.call_id, name: call.name, state: entry.state, ms: entry.finished - entry.started, replayed: !!entry.replayed }));
      return reply(200, { call_id: call.call_id, state: entry.state, output: entry.output, ms: entry.finished - entry.started, replayed: !!entry.replayed });
    }
    if (testDir && req.method === 'GET' && action === 'utterance') {
      const n = url.searchParams.get('n') ?? '';
      if (!/^\d{2}$/.test(n)) return reply(400, { error: 'n is two digits' });
      const audio = await readFile(join(testDir, `u${n}.24k.pcm`));
      res.writeHead(200, { 'content-type': 'application/octet-stream', 'cache-control': 'no-store' });
      return res.end(audio);
    }
    if (testDir && req.method === 'POST' && action === 'report') {
      const turn = JSON.parse(await readBody(req));
      await appendFile(join(stateDir, 'voice-test-report.jsonl'), JSON.stringify({ at: new Date().toISOString(), ...turn }) + '\n', { mode: 0o600 });
      console.log(JSON.stringify({ event: 'test-turn', n: turn.n, ok: turn.ok, calls: turn.calls, ms: turn.ms }));
      return reply(200, {});
    }
    if (req.method === 'GET' && action === 'ledger') {
      return reply(200, { calls: [...ledger.values()].map(({ entry }) => ({ call_id: entry.call_id, name: entry.name, args: entry.args, state: entry.state, output: entry.output && clip(entry.output, 300) })) });
    }
    return reply(404, { error: 'not found' });
  } catch (error) {
    console.log(JSON.stringify({ event: 'error', action, message: error.message }));
    return reply(error.status ?? 500, { error: error.message });
  }
});
server.listen(port, host, () => {
  const addresses = Object.values(networkInterfaces()).flat().filter(a => a.family === 'IPv4' && !a.internal).map(a => a.address);
  console.log(JSON.stringify({ event: 'ready', port: server.address().port, addresses, model, secretFile: file, device: device ?? null }));
});
