#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { createInterface } from 'node:readline/promises';
import { Writable } from 'node:stream';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { ModelRuntime, SettingsManager } from '@earendil-works/pi-coding-agent';
import { PokiClient } from './poki-client.mjs';
import { modelConfig, safeModelError } from './model-config.mjs';

const entries = { task: 'cli.mjs', imessage: 'imessage.mjs', telegram: 'telegram.mjs' };
const taskOptions = {
  device: { type: 'string' }, state: { type: 'string' }, model: { type: 'string' },
  auth: { type: 'string' }, 'service-tier': { type: 'string' }, context: { type: 'string' },
  'step-timeout': { type: 'string' }, help: { type: 'boolean', short: 'h' },
};
const help = `Usage: poki "task" [--device <UUID>] [--state <directory>] [--model <model>]
            [--auth chatgpt|api-key] [--service-tier <tier>] [--context <text>]
            [--step-timeout <seconds>]
       poki login [--auth chatgpt|api-key]
       poki status
       poki imessage --config <private JSON file> [--check]
       poki telegram --config <private JSON file> [--check]
With one connected physical phone, --device is optional. Use --device for a simulator.
Tasks accept /stop and corrections on stdin. Step timeout defaults to 60 seconds.
API keys belong only in OPENAI_API_KEY, never in command arguments.`;

function parse(args, options, allowPositionals = false) {
  try { return parseArgs({ args, options, allowPositionals }); }
  catch { throw new Error('Invalid arguments. Use poki --help. Do not pass credentials on the command line.'); }
}

function runtime() {
  return ModelRuntime.create({ modelsPath: null, allowModelNetwork: false, authPath: process.env.POKI_AGENT_AUTH_FILE });
}

async function chatGPTProvider(modelRuntime) {
  const credentials = await modelRuntime.listCredentials();
  return ['openai', 'openai-codex'].find(id => credentials.some(item => item.providerId === id && item.type === 'oauth'));
}

async function withMCP(action) {
  const client = new PokiClient();
  try {
    await client.open(`poki-cli-${randomUUID()}`);
    return await action(async name => {
      const result = await client.call(name);
      if (result.isError) throw new Error('Poki MCP could not report device status. Check the local service and phone connection.');
      return JSON.parse(result.content.find(item => item.type === 'text').text);
    });
  } finally { await client.close(); }
}

async function login(args) {
  const { values } = parse(args, { auth: { type: 'string' }, help: { type: 'boolean', short: 'h' } });
  if (values.help) { console.log('Usage: poki login [--auth chatgpt|api-key]\nChatGPT uses your existing sign-in. API access uses OPENAI_API_KEY from the environment.'); return; }
  const abort = new AbortController();
  let input;
  const stop = () => abort.abort();
  const ask = async prompt => {
    if (!process.stdin.isTTY) throw new Error('Interactive login needs a terminal. Run poki login --auth chatgpt in a terminal.');
    if (!input) {
      input = createInterface({ input: process.stdin, output: new Writable({ write(chunk, encoding, callback) { callback(); } }), terminal: true });
      input.on('SIGINT', stop);
    }
    console.log(prompt.message);
    if (prompt.type === 'select') for (const option of prompt.options) console.log(`  ${option.id}: ${option.label}`);
    const answer = await input.question('> ', { signal: prompt.signal ? AbortSignal.any([prompt.signal, abort.signal]) : abort.signal });
    return answer.trim();
  };
  process.once('SIGINT', stop);
  try {
    const auth = values.auth ?? await ask({ type: 'select', message: 'Choose Poki access (type chatgpt or api-key):', options: [
      { id: 'chatgpt', label: 'ChatGPT sign-in' }, { id: 'api-key', label: 'OpenAI API key from environment' },
    ] });
    if (!['chatgpt', 'api-key'].includes(auth)) throw new Error('Choose chatgpt or api-key. Run poki login --help.');
    if (auth === 'api-key') {
      console.log('Set OPENAI_API_KEY and POKI_AGENT_AUTH=api-key in your environment. Poki does not accept or store API keys.');
      if (!process.env.OPENAI_API_KEY?.trim()) { process.exitCode = 1; return; }
      console.log('API key is present in the environment (not sent or validated).');
      return;
    }
    const modelRuntime = await runtime();
    if (await chatGPTProvider(modelRuntime)) {
      console.log('ChatGPT: using existing sign-in. Set POKI_AGENT_AUTH=chatgpt to select it.');
      return;
    }
    await modelRuntime.login('openai', 'oauth', {
      signal: abort.signal,
      prompt: ask,
      notify(event) {
        if (event.type === 'auth_url') console.log(`Open this URL to sign in to ChatGPT:\n${event.url}\n${event.instructions ?? ''}`);
        else if (event.type === 'device_code') console.log(`Open ${event.verificationUri} and enter the displayed code: ${event.userCode}`);
        else console.log(event.message);
      },
    }, { agentName: 'Poki', getDeviceId: () => SettingsManager.create(process.cwd()).getOrCreateDeviceId() });
    if (!await chatGPTProvider(modelRuntime)) throw new Error('Sign-in was not saved.');
    console.log('ChatGPT sign-in saved. Set POKI_AGENT_AUTH=chatgpt to select it.');
  } catch {
    throw new Error('Poki login did not complete. Check your selection or browser sign-in and retry poki login.');
  } finally { input?.close(); process.removeListener('SIGINT', stop); }
}

async function status(args) {
  const { values } = parse(args, { help: { type: 'boolean', short: 'h' } });
  if (values.help) { console.log('Usage: poki status\nShow access method, model, service tier, MCP service and connected devices. No credentials are printed.'); return; }
  const config = modelConfig();
  const ready = config.auth === 'api-key' ? Boolean(process.env.OPENAI_API_KEY?.trim()) : Boolean(await chatGPTProvider(await runtime()));
  console.log(`Access: ${config.auth} (${ready ? 'configured' : 'not configured; run poki login'})\nModel: ${config.model}\nService tier: ${config.serviceTier}`);
  try {
    await withMCP(async call => {
      await call('poki_mcp_status');
      const { devices } = await call('list_devices');
      console.log('Poki MCP: connected');
      console.log(`Devices: ${devices.length}`);
      for (const device of devices) console.log(`  ${device.id}  ${device.name}  ${device.kind}${device.blocked ? ' (not ready)' : ''}`);
    });
  } catch {
    console.log('Poki MCP: unavailable. Start the local service with node src/daemon.mjs --port 0, using the same POKI_MCP_STATE_DIR.');
    process.exitCode = 1;
  }
}

async function main() {
  const args = process.argv.slice(2);
  if (!args.length || args[0] === '--help' || args[0] === '-h') { console.log(help); return; }
  const command = args[0];
  if (command === 'login') return login(args.slice(1));
  if (command === 'status') return status(args.slice(1));
  let target = 'task', forwarded = args;
  if (command === 'imessage' || command === 'telegram') {
    target = command; forwarded = args.slice(1);
    if (forwarded.includes('--help') || forwarded.includes('-h')) {
      console.log(`Usage: poki ${command} --config <private JSON file> [--state <directory>] [--step-timeout <seconds>] [--once] [--check]\n--check authenticates and reads only; no task or reply is sent.`);
      return;
    }
  } else {
    const { values, positionals } = parse(args, taskOptions, true);
    if (values.help) { console.log(help); return; }
    if (!positionals.join(' ').trim()) throw new Error('A task is required. Use poki --help.');
    if (!values.device) {
      const phones = await withMCP(async call => (await call('list_devices')).devices.filter(device => device.kind === 'physical'));
      if (phones.length !== 1) {
        console.error(phones.length ? 'Multiple phones connected. Specify --device <UUID>:' : 'No physical phone connected. Connect a phone, or specify --device for a simulator.');
        for (const phone of phones) console.error(`  ${phone.id}  ${phone.name}`);
        process.exitCode = 2; return;
      }
      forwarded = ['--device', phones[0].id, ...args];
    }
  }
  const entry = new URL(entries[target], import.meta.url);
  process.argv = [process.execPath, fileURLToPath(entry), ...forwarded];
  await import(entry.href);
}
main().catch(error => { console.error(safeModelError(error)); process.exitCode = 1; });
