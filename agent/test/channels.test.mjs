import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, mkdir, writeFile, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { makeMessages, addMessage } from './fixtures/messages.mjs';
import { makeTelegram } from './fixtures/telegram.mjs';
import { taskServices } from './fixtures/task-services.mjs';

for (const channel of ['bluebubbles', 'telegram']) {
  test(`${channel} CLI carries task, progress, system prompt handling, completion and failure through local HTTP services`, { timeout: 20000 }, async t => {
    const directory = await mkdtemp(join(tmpdir(), `poki-${channel}-e2e-`));
    const state = join(directory, 'state');
    const mcp = join(directory, 'mcp');
    const services = await taskServices(mcp);
    const api = await (channel === 'bluebubbles' ? makeMessages({ selfChat: true }) : makeTelegram());
    const config = join(directory, 'config.json');
    await writeFile(config, JSON.stringify({ device: 'synthetic-device', model: 'gpt-5.4', auth: 'api-key', serviceTier: 'fast',
      ...(channel === 'bluebubbles' ? { sender: 'allowed@example.test', chatGuid: 'any;-;allowed@example.test', context: 'Use only the synthetic fixture.' } : { allowedUsers: [101] }) }), { mode: 0o600 });
    const env = { ...process.env, IDEVICE_TOOLS: process.execPath, OPENAI_API_KEY: 'sk-local-channel-fixture', OPENAI_BASE_URL: services.modelURL,
      POKI_MCP_STATE_DIR: mcp, BLUEBUBBLES_URL: api.url, BLUEBUBBLES_PASSWORD: api.password ?? 'unused',
      TELEGRAM_API_URL: api.url, TELEGRAM_BOT_TOKEN: api.token ?? '123456:unused' };
    delete env.POKI_AGENT_SERVICE_TIER;
    const add = (text, allowed = true) => {
      if (channel !== 'bluebubbles') return api.add(text, allowed ? 101 : 999);
      addMessage(api, text, { sender: allowed ? 1 : 2, outgoing: 1, reaction: null });
      return addMessage(api, text, { sender: allowed ? 1 : 2, reaction: null });
    };
    add('Historical task must be skipped');
    const child = spawn(process.execPath, [`agent/${channel === 'bluebubbles' ? 'imessage' : 'telegram'}.mjs`, '--config', config, '--state', state],
      { cwd: resolve(import.meta.dirname, '../..'), env, stdio: ['ignore', 'pipe', 'pipe', 'ipc'] });
    child.on('message', message => deviceNotifications.push(message));
    const exited = once(child, 'exit');
    let transcript = '', started = false, handlerFailure;
    const replies = [];
    const starts = [];
    const completedAt = [];
    const expectedOpenings = ['I\'ll work on "Read the fixture status after the synthetic sign-in".', 'I\'ll work on "Fixture ready".', 'I\'ll work on "FAIL_CHANNEL_TASK".'];
    const deviceNotifications = [];
    const remember = chunk => {
      transcript += chunk;
      if (!started && transcript.includes('ready. Only new messages')) {
        started = true;
        add('Unauthorized task must not execute', false);
        add('Read the fixture status after the synthetic sign-in.');
      }
    };
    child.stdout.on('data', remember); child.stderr.on('data', remember);
    api.on('reply', (text, chat) => {
      try {
        if (channel === 'telegram') assert.equal(chat, '101');
        else assert.ok(!text.startsWith('🤖 Poki：'));
        if (expectedOpenings.includes(text)) starts.push({ replyIndex: replies.length, modelRequests: services.modelRequests.length, deviceCalls: services.deviceCalls.filter(call => call.name !== 'poki_mcp_status').length });
        replies.push(text);
        if (text === 'Fixture ready.' || text === 'completed: Fixture ready.') {
          completedAt.push(services.modelRequests.length);
          add(channel === 'bluebubbles' && completedAt.length === 1 ? text : 'FAIL_CHANNEL_TASK');
        }
        if (text === 'Synthetic failure returned to the original chat.' || text.startsWith('failed:')) child.kill('SIGTERM');
      } catch (error) { handlerFailure = error; child.kill('SIGTERM'); }
    });
    t.after(async () => {
      if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
      await exited;
      await api.close(); await services.close();
      if (process.env.POKI_CHANNEL_EVIDENCE) {
        const evidence = join(resolve(process.env.POKI_CHANNEL_EVIDENCE), channel);
        await mkdir(evidence, { recursive: true });
        await writeFile(join(evidence, 'worker-terminal.txt'), transcript);
        await writeFile(join(evidence, 'http-and-task-evidence.json'), JSON.stringify({
          real: ['channel CLI', 'MessageRunner', 'PhoneTask', 'pi SDK', 'MCP stdio bridge'],
          fake: ['BlueBubbles or Telegram HTTP API', 'OpenAI Responses API', 'MCP device service', 'sign-in and result data'],
          replies, messages: api.messages ?? api.sent, edits: api.edits, deviceCalls: services.deviceCalls,
          modelRequests: services.modelRequests, starts,
        }, null, 2));
      }
      await rm(directory, { recursive: true, force: true });
    });
    const [code, signal] = await exited;
    if (handlerFailure) throw handlerFailure;
    assert.equal(code, 0, `${transcript}\nSignal: ${signal}`);
    if (channel === 'bluebubbles') {
      assert.equal(starts.length, 3);
      assert.ok(starts[0].modelRequests > 0, 'Model work starts before delayed opening delivery');
      assert.ok(starts[0].deviceCalls > 0, 'Device work starts before delayed opening delivery');
      assert.deepEqual(replies.slice(starts[1].replyIndex, starts[2].replyIndex), [expectedOpenings[1], 'Fixture ready.']);
      assert.deepEqual([completedAt[0], completedAt[1] - completedAt[0], services.modelRequests.length - completedAt[1]], [9, 8, 5], 'Openings add no requests; failure now includes its final response and two verification responses');
      assert.deepEqual(replies.slice(starts[2].replyIndex), [expectedOpenings[2], 'Synthetic failure returned to the original chat.']);
      assert.ok(!replies.some(text => /^(planning|running|verifying):/.test(text)));
    }
    await assert.rejects(readFile(join(state, 'messages.lock')), { code: 'ENOENT' });
    assert.ok(replies.includes(channel === 'bluebubbles' ? 'Fixture ready.' : 'completed: Fixture ready.'));
    assert.ok(replies.includes(channel === 'bluebubbles' ? 'Synthetic failure returned to the original chat.' : 'failed: Synthetic failure returned to the original chat.'));
    assert.ok(services.deviceCalls.some(call => call.name === 'handle_alert'));
    assert.ok(services.modelRequests.every(request => request.service_tier === 'priority'));
    assert.ok(services.modelRequests.every(request => !request.tools.some(tool => ['hand_to_user', 'ask_user', 'report_uncertain'].includes(tool.name))));
    const taskDirectory = join(state, ...(channel === 'telegram' ? ['101'] : []), 'tasks');
    const records = await Promise.all((await readdir(taskDirectory)).map(async file => JSON.parse(await readFile(join(taskDirectory, file), 'utf8'))));
    assert.equal(records.length, channel === 'bluebubbles' ? 3 : 2);
    if (channel === 'bluebubbles') {
      assert.equal(records.filter(record => record.prompt === 'Fixture ready.').length, 1, 'User text identical to a consumed reply starts exactly one task');
    }
    assert.ok(deviceNotifications.some(message => message.type === 'poki-device-call' && message.name === 'list_elements'));
    const completed = records.find(record => record.prompt === 'Read the fixture status after the synthetic sign-in.');
    assert.equal(completed.result, 'Fixture ready.');
    assert.equal(completed.metrics.toolErrors, 1, 'A locked-screen tool error is returned to the model without stopping or waiting');
    if (channel === 'bluebubbles') assert.ok(records.every(record => record.context === 'Use only the synthetic fixture.'));
    assert.ok(records.every(record => !('need' in record) && !('handoff' in record)));
    assert.ok(!transcript.includes('\"phase\":\"waiting\"'));
    assert.equal(Boolean(completed.execution.learned), false);
    assert.ok(records.some(record => record.phase === 'failed'));
    assert.equal(services.modelRequests.some(request => JSON.stringify(request).includes('Unauthorized task')), false);
    assert.ok(services.deviceCalls.some(call => call.name === 'list_elements'));
    assert.ok(!transcript.includes(env.OPENAI_API_KEY) && !transcript.includes(env.BLUEBUBBLES_PASSWORD) && !transcript.includes(env.TELEGRAM_BOT_TOKEN));
    if (channel === 'telegram') {
      assert.ok(api.edits.length >= 1);
      assert.ok(api.messages.some(message => message.text === 'completed: Fixture ready.'));
      assert.ok(api.messages.every(message => message.chat.id === 101));
    } else assert.ok(api.sent.every(message => message.chatGuid === 'any;-;allowed@example.test'));
    if (process.env.POKI_CHANNEL_EVIDENCE) {
      const evidence = join(resolve(process.env.POKI_CHANNEL_EVIDENCE), channel);
      await mkdir(evidence, { recursive: true });
      await writeFile(join(evidence, 'task-records.json'), JSON.stringify(records, null, 2));
    }
  });
}
