import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from './fixture.mjs';

test('A batch with no device and two phones reports the device choice instead of crashing in the read-back', async t => {
  const f = await fixture(t);
  await f.set({ twoPhones: true, label: 'Ready' });
  const result = await f.call('batch_commands', { commands: [{ tool: 'launch_app', arguments: { bundle_id: 'local.fixture' } }] });
  assert.equal(result.isError, true);
  const text = result.content.map(block => block.text ?? '').join('\n');
  assert.doesNotMatch(text, /Cannot read properties of undefined/);
  assert.match(text, /Multiple devices match/);
  assert.equal((await f.events()).filter(event => event.op === 'launch_app').length, 0, 'Nothing may launch while the device is ambiguous');
});

test('a batch pinned to one simulator enumerates once and reads back that simulator', async t => {
  const f = await fixture(t);
  await f.set({ simulatorOnly: true, simulatorBooted: true, secondSimulator: true,
    labels: { 'fixture-sim': 'First screen', 'fixture-sim-2': 'Second screen' } });
  await f.call('select_device', { device: 'fixture-sim' });
  const before = (await f.events()).length;
  const info = { tool: 'get_device_info', arguments: { device: 'fixture-sim-2' } };
  const result = await f.call('batch_commands', { commands: [info, info] });
  assert.ok(!result.isError, JSON.stringify(result.content));
  const summary = JSON.parse(result.content.at(-1).text);
  assert.equal(summary.completed_steps, 2);
  assert.deepEqual(summary.screen.text, ['Button: Second screen']);
  const events = (await f.events()).slice(before);
  assert.equal(events.filter(event => event.tool === 'python3').length, 1);
  const next = await f.call('get_device_info');
  assert.equal(JSON.parse(next.content[0].text).id, 'fixture-sim');
});
