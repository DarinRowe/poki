import test from 'node:test';
import assert from 'node:assert/strict';
import { writeFile } from 'node:fs/promises';
import sharp from 'sharp';
import { fixture, value } from './fixture.mjs';

const screen = (width, height, label) => [
  { role: 'Application', frame: { x: 0, y: 0, width, height } },
  { role: 'Button', label, object_id: 'button', frame: { x: 20, y: 40, width: 40, height: 20 } },
];
const captures = result => result._meta.timing.stages.filter(stage => stage.phase === 'screen_capture').length;

test('a verified USB portrait viewport avoids capture and maps a tap to the same HID point', async t => {
  const f = await fixture(t, { extraEnv: () => ({ POKI_DIRECT_REF: '1', POKI_CONDITIONAL_WAIT: '1' }) });
  await f.set({ orientation: 1, screenWidth: 100, screenHeight: 200, launched: true,
    elements: screen(100, 200, 'Open'), afterInput: { elements: screen(100, 200, 'Opened') } });
  const read = await f.call('observe_device', { fallback: 'hybrid' });
  assert.equal(captures(read), 0);
  const observed = value(read);
  assert.deepEqual([observed.width, observed.height], [100, 200]);
  assert.equal(observed.observation.capture_completed_at, undefined);
  const result = await f.call('tap', { ref: observed.elements.find(e => e.label === 'Open').ref,
    expect: { text: 'Opened' } });
  assert.equal(value(result).expectation.matched, true);
  assert.equal(captures(result), 0);
  const taps = (await f.events()).filter(event => event.op === 'tap');
  assert.equal(taps.length, 1);
  assert.deepEqual([taps[0].request.x, taps[0].request.y], [
    Math.round(40 / 99 * 65535), Math.round(50 / 199 * 65535),
  ]);
});

test('a root mismatch uses one real frame for image fallback', async t => {
  const f = await fixture(t);
  await f.set({ orientation: 1, screenWidth: 100, screenHeight: 200,
    elements: screen(90, 180, 'Open') });
  const result = await f.call('observe_device', { fallback: 'image', ax_hint: 'Missing' });
  assert.equal(captures(result), 1);
  assert.equal(value(result).source, 'image');
  assert.ok(value(result).observation.capture_completed_at);
  assert.ok(result.content.some(item => item.type === 'image'));
});

test('rotation after a geometry-only observation invalidates the old reference', async t => {
  const f = await fixture(t, { extraEnv: () => ({ POKI_DIRECT_REF: '1' }) });
  await f.set({ orientation: 1, screenWidth: 100, screenHeight: 200, launched: true,
    elements: screen(100, 200, 'Open') });
  const initial = await f.call('observe_device', { fallback: 'hybrid' });
  assert.equal(captures(initial), 0);
  const { ref } = value(initial).elements.find(e => e.label === 'Open');
  const image = await sharp({ create: { width: 200, height: 100, channels: 3, background: 'white' } }).png().toBuffer();
  await writeFile(f.image, image);
  await f.set({ orientation: 3, screenWidth: 100, screenHeight: 200, launched: true,
    elements: screen(200, 100, 'Open') });
  const result = await f.call('tap', { ref });
  assert.equal(captures(result), 1);
  assert.equal(value(result).outcome, 'not_sent');
  assert.equal((await f.events()).filter(event => event.op === 'tap').length, 0);
  const current = value(await f.call('observe_device', { fallback: 'hybrid' }));
  assert.deepEqual([current.width, current.height], [200, 100]);
});
