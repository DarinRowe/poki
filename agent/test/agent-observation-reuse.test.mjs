import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { once } from 'node:events';
import { taskServices } from './fixtures/task-services.mjs';
import { PhoneTask } from '../task-runner.mjs';

async function scenario(t, postActionObservation, batch = false, quickScreen) {
  const directory = await mkdtemp(join(tmpdir(), 'poki-reuse-'));
  const services = await taskServices(join(directory, 'mcp'), { route: true, postActionObservation, pidOnlyReceipt: batch,
    scrollResults: quickScreen ? [{ sent: true, screen: quickScreen }] : [], execution: [
    ['report_plan', { title: 'Write fixture', steps: ['Open app', 'Fill field'], currentStep: 1 }],
    ['launch_app', { bundle_id: 'org.example.channel-fixture' }],
    ['report_plan', { title: 'Write fixture', steps: ['Open app', 'Fill field'], currentStep: 2 }],
    ...(quickScreen ? [
      batch ? ['batch_commands', { commands: [{ tool: 'scroll', arguments: { direction: 'down', observe: 'quick' } }] }]
        : ['scroll', { direction: 'down', observe: 'quick' }],
      ...(quickScreen.elements.length ? [['finish_task', { success: true, summary: 'Too early', details: [], answer: { kind: 'action' } }]] : []),
    ] : []),
    batch ? ['batch_commands', { commands: [{ tool: 'fill', arguments: { field: 'Value', text: 'Example', submit: false } }] }]
      : ['fill', { field: 'Value', text: 'Example', submit: false }],
    ['finish_task', { success: true, summary: 'Saved: Example',
      details: [{ label: 'Value', value: 'Example' }], answer: { kind: 'action' } }],
  ] });
  const env = { ...process.env };
  Object.assign(process.env, { IDEVICE_TOOLS: process.execPath, POKI_MCP_STATE_DIR: join(directory, 'mcp'),
    OPENAI_BASE_URL: services.modelURL, OPENAI_API_KEY: 'sk-local-channel-fixture', POKI_AGENT_AUTH: 'api-key' });
  const task = new PhoneTask('Fill the fixture field with Example', 'synthetic-device',
    { stateDirectory: join(directory, 'state'), auth: 'api-key', model: 'gpt-5.4', stepTimeout: 10 });
  t.after(async () => {
    await task.close(); await services.close();
    for (const key of Object.keys(process.env)) if (!(key in env)) delete process.env[key];
    Object.assign(process.env, env);
    await rm(directory, { recursive: true, force: true });
  });
  const closed = once(task, 'closed');
  void task.start(); await closed;
  assert.equal(task.snapshot.failure, null, 'The synthetic task must complete verification');
  return { listCalls: services.deviceCalls.filter(c => c.name === 'list_elements').length,
    trace: task.trace, deviceCalls: services.deviceCalls, modelRequests: services.modelRequests };
}

test('Agent reuses eligible receipt and omits the second explicit list_elements read', { timeout: 60000 }, async t => {
  const reused = await scenario(t, true);
  assert.equal(reused.listCalls, 1);
  assert.ok(reused.trace.some(e => e.tool === 'post_action_observation' && e.reused && e.args.source === 'action_receipt'));
  assert.equal(reused.deviceCalls.find(c => c.name === 'fill').args.return_observation, true);
  assert.equal(reused.deviceCalls.find(c => c.name === 'fill').args.post_action_ocr, undefined,
    'Ordinary Agent must not add image/OCR work by default');
  const toolOutputs = reused.modelRequests
    .filter(request => !request.tools?.some(tool => tool.name === 'report_verification'))
    .flatMap(request => request.input.filter(item => item.type === 'function_call_output'));
  assert.ok(toolOutputs.length, 'The Agent sent execution tool outputs to the model');
  assert.ok(toolOutputs.every(item => !JSON.stringify(item.output).includes('post_action_observation')),
    'The model must receive one trimmed element list, not the nested receipt and a duplicate');
});
test('Agent retains list_elements fallback for a legacy receipt', { timeout: 60000 }, async t => {
  const legacy = await scenario(t, false);
  assert.equal(legacy.listCalls, 2);
  assert.ok(!legacy.trace.some(e => e.tool === 'post_action_observation'));
});


test('Agent uses a PID-bound terminal batch observation without another list_elements call', async t => {
  const reused = await scenario(t, true, true);
  assert.equal(reused.listCalls, 2, 'One launch read and one batch readback');
  assert.equal(reused.trace.filter(e => e.tool === 'post_action_observation' && e.reused).length, 1);
  assert.equal(reused.trace.filter(e => e.tool === 'list_elements').length, 1);
});

test('Agent uses quick scroll evidence for browsing and still requires a final observation', async t => {
  const screen = { source: 'accessibility', screen_stable: false, observation: { device: 'synthetic-device' },
    elements: [{ label: 'Quick row' }] };
  for (const batch of [false, true]) await t.test(batch ? 'batch' : 'single scroll', async t => {
    const result = await scenario(t, true, batch, screen);
    const calls = result.deviceCalls.map(call => call.name);
    const scroll = calls.indexOf('scroll');
    assert.ok(scroll >= 0);
    assert.equal(calls[scroll + 1], 'fill');
    assert.notEqual(result.deviceCalls[scroll].args.return_observation, true);
    const outputs = JSON.stringify(result.modelRequests.flatMap(request => request.input));
    assert.match(outputs, /Quick row/);
    assert.match(outputs, /Observe the result after the last action/);
    assert.equal(result.trace.find(entry => entry.tool === 'scroll').result.screen.elements[0].label, 'Quick row');
  });
});

test('Agent still reads the screen when a quick sample is unavailable', async t => {
  const result = await scenario(t, true, false, { source: 'unavailable', screen_stable: false, elements: [] });
  const calls = result.deviceCalls.map(call => call.name);
  assert.equal(calls[calls.indexOf('scroll') + 1], 'list_elements');
});
