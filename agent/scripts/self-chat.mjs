import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createInterface } from 'node:readline';
import { readFile, access } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { constants } from 'node:fs';
import { parseArgs } from 'node:util';
import { PiSession } from '../pi-session.mjs';
import { PokiClient } from '../poki-client.mjs';
import { checkDeviceTools } from '../device-preflight.mjs';

const { values } = parseArgs({ options: { config: { type: 'string' }, state: { type: 'string' }, check: { type: 'boolean' } } });
assert.ok(values.config && values.state, 'Pass --config and --state for this self-chat instance.');
const privateDir = resolve(values.state);
const configPath = resolve(values.config);
process.env.POKI_MCP_STATE_DIR = join(privateDir, 'mcp');
const config = JSON.parse(await readFile(configPath, 'utf8'));
const checking = values.check ?? false;
try { await checkDeviceTools(); }
catch (error) { console.error(error.message); process.exit(1); }
for (const name of ['poki-native', 'ocr']) await access(resolve('build', name), constants.X_OK);
const model = new PiSession(config);
try {
  await model.open();
  await model.request('thread/start', { developerInstructions: 'Startup configuration check only.', dynamicTools: [] });
  console.log('Model credentials and configured model resolved. No model response requested.');
} finally { await model.close(); }
let worker;
let stopping = false;
const stop = () => { stopping = true; worker?.kill('SIGTERM'); };
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
const daemon = spawn(process.execPath, ['src/daemon.mjs', '--port', '0'], { stdio: ['ignore', 'pipe', 'inherit'] });
const daemonExit = once(daemon, 'exit');
const client = new PokiClient();
const lines = createInterface({ input: daemon.stdout });
const ready = (async () => {
  for await (const line of lines) {
    if (JSON.parse(line).event === 'ready') return;
  }
  throw new Error('The isolated MCP stopped before readiness.');
})();
let deviceUsed = false;
try {
  await ready;
  const tools = await client.open(`esp65-self-chat-check-${process.pid}`);
  assert.ok(tools.some(tool => tool.name === 'observe_device'));
  console.log('Isolated MCP ready on a private random port. No device call made during startup.');
  await client.close();
  if (!stopping) {
    worker = spawn(process.execPath, ['agent/imessage.mjs', '--config', configPath, '--state', join(privateDir, 'worker'),
      ...(checking ? ['--check'] : [])], { stdio: ['inherit', 'inherit', 'inherit', 'ipc'] });
    worker.on('message', message => { if (message?.type === 'poki-device-call') deviceUsed = true; });
    const [code, signal] = await once(worker, 'exit');
    worker = undefined;
    process.exitCode = code ?? (signal === 'SIGTERM' && stopping ? 0 : 1);
  }
} finally {
  lines.close();
  if (worker) { worker.kill('SIGTERM'); await once(worker, 'exit'); }
  try {
    if (deviceUsed) {
      let lease;
      try {
        await client.open(`esp65-self-chat-cleanup-${process.pid}`);
        const acquired = await client.call('acquire_device', { device: config.device, ttl_seconds: 120 });
        assert.ok(!acquired.isError, 'Cleanup could not acquire the device.');
        lease = JSON.parse(acquired.content.find(item => item.type === 'text').text);
        const foreground = await client.call('get_foreground_app', { device: config.device });
        assert.ok(!foreground.isError, 'Cannot check cleanup foreground.');
        const current = JSON.parse(foreground.content.find(item => item.type === 'text').text);
        assert.ok(['com.apple.Preferences', 'com.apple.springboard'].includes(current.bundle_id), 'The foreground was changed by the user.');
        const home = await client.call('system_gesture', { device: config.device, gesture: 'go_home' });
        assert.ok(!home.isError, 'Cleanup could not return the phone home.');
        console.log('Phone returned home.');
      } catch {
        console.error('Phone cleanup needs operator attention.');
        process.exitCode = 1;
      } finally {
        try { if (lease) await client.call('release_device', { lease_id: lease.lease_id }); }
        finally { await client.close(); }
      }
    }
  } finally {
    daemon.kill('SIGTERM');
    await daemonExit;
    process.removeListener('SIGINT', stop);
    process.removeListener('SIGTERM', stop);
    console.log('Isolated MCP stopped.');
  }
}
