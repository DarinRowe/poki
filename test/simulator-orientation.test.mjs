import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { fixture, value } from './fixture.mjs';

for (const [orientation, expected] of [
  ['landscape_left', { x: 0.3, y: 0.6 }],
  ['landscape_right', { x: 0.7, y: 0.4 }],
]) {
  test(`simulator maps ${orientation} screen points to portrait HID coordinates`, async t => {
    const f = await fixture(t);
    await f.set({ simulatorOnly: true, simulatorBooted: true });
    await sharp({ create: { width: 200, height: 100, channels: 3, background: 'white' } }).png().toFile(f.image);
    const rotation = await f.call('rotate', { orientation });
    assert.equal(value(rotation).sent, true);
    const result = await f.call('tap', { x: 80, y: 30, verify: false });
    assert.equal(value(result).sent, true);
    const events = (await f.events()).find(event => event.op === 'hid').request.events;
    assert.deepEqual(events.filter(event => event.payload?.pointOne).map(event => event.payload.pointOne),
      [expected, expected]);
  });
}

test('simulator refuses coordinates on an unconfirmed landscape screen', async t => {
  const f = await fixture(t);
  await f.set({ simulatorOnly: true, simulatorBooted: true });
  await sharp({ create: { width: 200, height: 100, channels: 3, background: 'white' } }).png().toFile(f.image);
  const result = await f.call('tap', { x: 80, y: 30, verify: false });
  assert.equal(result.isError, true);
  assert.equal(value(result).reason, 'orientation_unconfirmed');
  assert.equal(value(result).outcome, 'not_sent');
  assert.equal((await f.events()).some(event => event.op === 'hid'), false);
});
