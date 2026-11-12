import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture, value } from './fixture.mjs';

const enabled = { extraEnv: () => ({ POKI_DIRECT_REF: '1', POKI_CONDITIONAL_WAIT: '1' }) };
const root = (width = 100, height = 200) => ({ role: 'Application', frame: { x: 0, y: 0, width, height } });
const control = (label, object_id, y = 35) => ({ role: 'Button', label, object_id, enabled: true, frame: { x: 20, y, width: 40, height: 20 } });
const page = (elements, foregroundPid = 4242) => ({ launched: true, foregroundPid, elements: [root(), ...elements] });
const ref = async (f, label) => value(await f.call('observe_device', { fallback: 'hybrid' })).elements.find(e => e.label === label).ref;
const taps = async f => (await f.events()).filter(e => e.op === 'tap').length;

test('verified reference and new condition share fresh AX reads with the batch receipt', async t => {
  const f = await fixture(t, enabled);
  await f.set({ ...page([control('Start', 'o1')]), afterInput: page([control('Stop', 'o2')]) });
  const start = await ref(f, 'Start');
  const result = await f.call('batch_commands', { return_observation: true, commands: [
    { tool: 'tap', arguments: { ref: start, expect: { text: 'Stop', state: 'enabled' } } },
  ] });
  assert.ok(!result.isError, JSON.stringify(result));
  const action = JSON.parse(result.content[1].text);
  const summary = JSON.parse(result.content.at(-1).text);
  assert.equal(action.target_source, 'validated_reference');
  assert.equal(action.expectation.matched, true);
  assert.ok(summary.post_action_observation.elements.some(e => e.label === 'Stop' && e.ref));
  assert.equal(await taps(f), 1);
  const phases = result._meta.timing.stages.map(s => s.phase);
  assert.equal(phases.filter(p => p === 'accessibility').length, 2);
  assert.ok(!phases.includes('batch_readback'));
  assert.ok(!phases.includes('screen_capture'));
});

test('guarded references refuse externally changed targets, foreground, rotation and overlays', async t => {
  const f = await fixture(t, enabled);
  for (const state of [
    page([control('Start', 'o1', 65)]),
    page([control('Start', 'o1')], 4243),
    { ...page([control('Start', 'o1')]), elements: [root(200, 100), control('Start', 'o1')] },
    page([control('Start', 'o1'), { ...control('Overlay', 'o2'), role: 'Alert' }]),
    page([control('Start', 'o1'), control('Same identity', 'o1', 65)]),
    page([control('Start', 'o1'), control('Cover', 'o2')]),
  ]) {
    await f.set(page([control('Start', 'o1')]));
    const start = await ref(f, 'Start');
    await f.set(state);
    const r = await f.call('tap', { ref: start });
    assert.equal(r.isError, true);
    assert.equal(value(r).outcome, 'not_sent');
  }
  assert.equal(await taps(f), 0);
});

test('already satisfied and timed-out expectations cannot masquerade as action success', async t => {
  const f = await fixture(t, enabled);
  await f.set(page([control('Start', 'o1'), control('Stop', 'o2', 65)]));
  let start = await ref(f, 'Start');
  const existing = await f.call('tap', { ref: start, expect: { text: 'Stop' } });
  assert.equal(existing.isError, true);
  assert.equal(value(existing).sent, false);
  assert.equal(await taps(f), 0);

  await f.set(page([control('Start', 'o1')]));
  start = await ref(f, 'Start');
  const stopped = await f.call('batch_commands', { stop_on_error: false, commands: [
    { tool: 'tap', arguments: { ref: start, expect: { text: 'Stop', timeout_seconds: 0.2 } } },
    { tool: 'press_key', arguments: { key: 'return' } },
  ] });
  assert.equal(stopped.isError, true);
  const action = JSON.parse(stopped.content[1].text);
  const summary = JSON.parse(stopped.content.at(-1).text);
  assert.equal(action.sent, true);
  assert.equal(action.expectation.matched, false);
  assert.equal(summary.recovery.outcome, 'verify');
  assert.equal(summary.recovery.unattempted_steps[0].tool, 'press_key');
  assert.equal(await taps(f), 1);
  assert.equal((await f.events()).filter(e => e.op === 'key').length, 0);
});

test('an overlay refusal explains recovery and invalidates the blocked reference', async t => {
  const f = await fixture(t, enabled);
  const target = control('Open details', 'item', 90);
  const sheet = { ...control('Session notice', 'sheet', 20), role: 'Sheet' };
  const later = control('Continue browsing', 'dismiss', 55);
  await f.set(page([target]));
  const stale = await ref(f, target.label);
  await f.set(page([sheet, later, target]));
  const blocked = await f.call('tap', { ref: stale });
  const refusal = value(blocked);
  assert.equal(refusal.reason, 'blocking_overlay');
  assert.equal(refusal.outcome, 'not_sent');
  assert.equal(refusal.recovery.tool, 'handle_alert');
  assert.ok(refusal.blocker.visible_buttons.includes(later.label));
  assert.equal(await taps(f), 0);

  const repeated = await f.call('tap', { ref: stale });
  assert.equal(value(repeated).reason, 'reference_requires_fresh_observation');
  assert.ok(!repeated._meta.timing.stages.some(stage => stage.phase === 'accessibility'));

  const observed = value(await f.call('observe_device', { fallback: 'hybrid' }));
  assert.equal(observed.recovery.tool, 'handle_alert');
  const blockedBatch = await f.call('batch_commands', { stop_on_error: false, commands: [
    { tool: 'tap_text', arguments: { text: target.label, exact: true } },
    { tool: 'press_key', arguments: { key: 'return' } },
  ] });
  assert.equal(blockedBatch.isError, true);
  assert.equal(JSON.parse(blockedBatch.content.at(-1).text).stop_reason, 'blocked_by_overlay');
  assert.equal(await taps(f), 0);
});

test('exact tap text uses OCR rather than an AX substring', async t => {
  const f = await fixture(t, enabled);
  await f.set({
    ...page([control('Delivery options nearby', 'decoy', 130)]),
    ocrElements: [{ text: 'Delivery options', x: 20, y: 60, width: 40, height: 20 }],
  });
  const result = await f.call('tap_text', { text: 'Delivery options', exact: true, verify: false });
  assert.ok(!result.isError, JSON.stringify(result));
  const actions = (await f.events()).filter(e => e.op === 'tap');
  assert.equal(actions.length, 1);
  assert.equal(actions[0].request.y, Math.round(70 / 199 * 65535));
});
