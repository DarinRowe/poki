import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { PiSession } from '../pi-session.mjs';

function response(res, tool = false, tier = 'default', model = 'gpt-5.4') {
  const item = tool
    ? { type: 'function_call', id: 'fc_test', call_id: 'call_test', name: 'record_result', arguments: '{"value":"one action"}', status: 'completed' }
    : { type: 'message', id: 'msg_test', role: 'assistant', status: 'completed', content: [{ type: 'output_text', text: 'DONE', annotations: [] }] };
  const result = { id: 'resp_test', object: 'response', status: 'completed', model, service_tier: tier, output: [item], usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15, input_tokens_details: { cached_tokens: 0 }, output_tokens_details: { reasoning_tokens: 0 } } };
  res.writeHead(200, { 'content-type': 'text/event-stream' });
  for (const event of [
    { type: 'response.created', response: { ...result, status: 'in_progress', output: [] } },
    { type: 'response.output_item.added', output_index: 0, item },
    { type: 'response.output_item.done', output_index: 0, item },
    { type: 'response.completed', response: result },
  ]) res.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
  res.end();
}

async function exercise(t, mode) {
  const directory = await mkdtemp(join(tmpdir(), 'poki-openai-test-'));
  const secret = 'sk-fake-local-protocol-test';
  const before = { ...process.env };
  const originalFetch = globalThis.fetch;
  const requests = [], warnings = [], messages = [], actions = [];
  const server = http.createServer(async (req, res) => {
    let raw = ''; for await (const chunk of req) raw += chunk;
    const payload = JSON.parse(raw);
    if (mode === 'fast-defaults') { assert.equal(payload.model, 'gpt-6.1-terra'); assert.equal(payload.service_tier, 'priority'); }
    assert.equal(payload.reasoning?.effort, 'low');
    requests.push(payload);
    if (req.headers.authorization !== `Bearer ${secret}`) { res.writeHead(401).end(); return; }
    if (mode === 'rejected' && requests.length === 2) {
      res.writeHead(400, { 'content-type': 'application/json' }).end(JSON.stringify({ error: { message: 'service_tier priority is not supported for this account', type: 'invalid_request_error', param: 'service_tier' } })); return;
    }
    if (mode === 'auth-error') {
      res.writeHead(401, { 'content-type': 'application/json' }).end(JSON.stringify({ error: { message: `Invalid API key: ${secret}`, type: 'authentication_error' } })); return;
    }
    response(res, mode === 'rejected' && requests.length === 1, mode === 'rejected' && requests.length === 1 ? 'priority' : mode === 'fast-defaults' ? 'priority' : 'default', payload.model);
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const base = `http://127.0.0.1:${server.address().port}`;
  process.env.OPENAI_API_KEY = secret;
  process.env.OPENAI_BASE_URL = `${base}/v1`;
  delete process.env.POKI_AGENT_SERVICE_TIER;
  globalThis.fetch = (url, options) => {
    assert.equal(new URL(typeof url === 'string' ? url : url.url ?? url).origin, base, 'Protocol tests must never contact a live provider');
    return originalFetch(url, options);
  };
  const session = new PiSession({ auth: 'api-key', ...(mode === 'fast-defaults' ? { serviceTier: undefined } : { model: 'gpt-5.4', serviceTier: mode === 'rejected' || mode === 'downgraded' ? 'priority' : 'default' }), evidenceDirectory: directory });
  t.after(async () => {
    session.close(); globalThis.fetch = originalFetch;
    for (const key of Object.keys(process.env)) if (!(key in before)) delete process.env[key];
    Object.assign(process.env, before);
    server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    await rm(directory, { recursive: true, force: true });
  });
  session.on('warning', warning => warnings.push(warning));
  const done = new Promise((resolveDone, reject) => {
    session.on('disconnected', reject);
    session.on('message', message => {
      messages.push(message);
      if (message.method === 'item/tool/call') {
        actions.push(message.params.arguments.value);
        session.send({ id: message.id, result: { success: true, contentItems: [{ type: 'inputText', text: 'Recorded' }] } });
      }
      if (message.method === 'turn/completed') resolveDone(message.params.turn);
    });
  });
  await session.open();
  const { thread } = await session.request('thread/start', { developerInstructions: 'Use record_result when needed, then answer DONE.', dynamicTools: [{ name: 'record_result', description: 'Record a result', inputSchema: { type: 'object', properties: { value: { type: 'string' } }, required: ['value'], additionalProperties: false } }] });
  await session.request('turn/start', { threadId: thread.id, effort: mode === 'fast-defaults' ? 'high' : 'low', input: [{ type: 'text', text: 'Run the protocol check.' }] });
  const turn = await done;
  const evidence = (await Promise.all((await readdir(directory)).filter(name => name.endsWith('.jsonl')).map(name => readFile(join(directory, name), 'utf8')))).join('');
  assert.ok(!JSON.stringify(messages).includes(secret) && !evidence.includes(secret), 'Credentials must not appear in events or evidence');
  if (mode === 'auth-error') {
    assert.equal(turn.status, 'failed'); assert.match(turn.error.message, /redacted/); assert.equal(requests.length, 1);
  } else {
    assert.equal(turn.status, 'completed');
    assert.ok(messages.some(message => message.params?.item?.text === 'DONE'));
    if (mode === 'fast-defaults') { assert.equal(requests.length, 1); assert.equal(warnings.length, 0); assert.match(evidence, /"service_tier":"priority"/); }
    if (mode === 'default') { assert.equal(requests.length, 1); assert.equal(requests[0].service_tier, 'default'); assert.equal(warnings.length, 0); }
    if (mode === 'rejected') {
      assert.equal(requests.length, 3);
      assert.equal(requests[0].service_tier, 'priority'); assert.equal(requests[1].service_tier, 'priority');
      assert.equal(requests[2].service_tier, 'default');
      assert.deepEqual(actions, ['one action']); assert.equal(warnings.length, 1);
    }
    if (mode === 'downgraded') {
      assert.equal(requests.length, 1); assert.equal(warnings.length, 1);
      assert.equal(session.options.serviceTier, 'priority', 'A server downgrade must not erase the requested tier');
      const second = new Promise(resolve => session.on('message', message => { if (message.method === 'turn/completed') resolve(); }));
      await session.request('turn/start', { input: [{ type: 'text', text: 'Another minimal response.' }] });
      await second;
      assert.equal(requests[1].service_tier, 'priority', 'Every later request must retain Fast');
    }
  }
}

for (const mode of ['default', 'rejected', 'downgraded', 'auth-error', 'fast-defaults']) {
  test(`OpenAI protocol: ${mode}`, { timeout: 20000 }, t => exercise(t, mode));
}
