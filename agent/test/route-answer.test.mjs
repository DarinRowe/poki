import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { answerCurrentScreen } from '../answer-current-screen.mjs';

test('Route answers use changed current activity names and times and reject unknown references', async t => {
  const before = { ...process.env }, originalFetch = globalThis.fetch, requests = [];
  const selections = [
    { complete: true, items: [{ ref: 'e20', field: 'label' }] },
    { complete: true, items: [{ ref: 'e21', field: 'label' }] },
    { complete: true, items: [{ ref: 'e999', field: 'label' }] },
  ];
  const server = http.createServer(async (req, res) => {
    let body = ''; for await (const chunk of req) body += chunk;
    const payload = JSON.parse(body); requests.push(payload);
    assert.equal((payload.tools ?? []).length, 0, 'The answer model cannot operate the phone');
    const selection = selections[requests.length - 1];
    if (!selection) { res.writeHead(500).end(); return; }
    const item = { type: 'message', id: 'msg_answer', role: 'assistant', status: 'completed', content: [{ type: 'output_text', text: JSON.stringify(selection), annotations: [] }] };
    const response = { id: 'resp_answer', object: 'response', status: 'completed', model: 'gpt-5.4', output: [item], usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15, input_tokens_details: { cached_tokens: 0 }, output_tokens_details: { reasoning_tokens: 0 } } };
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    for (const event of [
      { type: 'response.created', response: { ...response, status: 'in_progress', output: [] } },
      { type: 'response.output_item.added', output_index: 0, item },
      { type: 'response.output_item.done', output_index: 0, item },
      { type: 'response.completed', response },
    ]) res.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
    res.end();
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const origin = `http://127.0.0.1:${server.address().port}`;
  process.env.OPENAI_API_KEY = 'sk-fake-route-answer';
  process.env.OPENAI_BASE_URL = origin + '/v1';
  delete process.env.POKI_AGENT_SERVICE_TIER;
  globalThis.fetch = (url, options) => {
    assert.equal(new URL(typeof url === 'string' ? url : url.url ?? url).origin, origin);
    return originalFetch(url, options);
  };
  t.after(async () => {
    globalThis.fetch = originalFetch;
    for (const key of Object.keys(process.env)) if (!(key in before)) delete process.env[key];
    Object.assign(process.env, before);
    server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
  });
  const old = 'Old Astronomy Talk, Friday 17:00 GMT-8';
  const current = 'New Robotics Workshop, Saturday 18:30 GMT-8';
  const run = async (ref, label) => {
    let responses = 0;
    const answer = await answerCurrentScreen({ prompt: 'Read the Los Angeles activity names and times.',
      observation: { source: 'accessibility', foreground: { name: 'Luma' }, truncated: false,
        elements: [{ ref: 'e1', role: 'Button', label: 'Los Angeles', trait_names: ['Header'] }, { ref, role: 'Button', label }] },
      modelConfig: { auth: 'api-key', model: 'gpt-5.4' }, onResponse: () => responses++,
    });
    assert.equal(responses, 1, 'Only one answer response is needed');
    return answer;
  };
  assert.equal((await run('e20', old)).summary, old);
  const changed = await run('e21', current);
  assert.equal(changed.success, true); assert.equal(changed.summary, current);
  assert.ok(!JSON.stringify(requests[1]).includes(old), 'A previous answer is not part of current-screen evidence');
  const invalid = await run('e21', current);
  assert.equal(invalid.success, false); assert.deepEqual(invalid.details, []);
  assert.equal(requests.length, 3);
});
