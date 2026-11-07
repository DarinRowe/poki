import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture, value } from './fixture.mjs';

test('observe_device omits PNG only when requested', async t => {
  const f = await fixture(t);
  const defaultResult = await f.call('observe_device', { source: 'ocr' });
  const compactResult = await f.call('observe_device', { source: 'ocr', include_image: false });
  assert.ok(!defaultResult.isError);
  assert.ok(!compactResult.isError);
  assert.ok(defaultResult.content.some(item => item.type === 'image'));
  assert.ok(!compactResult.content.some(item => item.type === 'image'));
  const first = value(defaultResult), second = value(compactResult);
  assert.notEqual(first.observation.id, second.observation.id);
  assert.equal(second.observation.atomic, false);
  assert.equal(second.source, 'ocr');
  assert.equal(second.prompt.status, 'checked');
  assert.ok(second.elements.length > 0);
  assert.ok(second.elements.every(element => /^e\d+$/.test(element.ref)));
  const screenshots = (await f.events()).filter(event => event.args?.includes('screenshot'));
  assert.equal(screenshots.length, 2, 'Internal capture still occurs for structured-only responses');
});
test('missing prompt OCR remains explicit without an image attachment', async t => {
  const f = await fixture(t);
  await f.set({ ocrUnavailable: true });
  const result = await f.call('observe_device', { include_image: false });
  assert.ok(!result.isError);
  const data = value(result);
  assert.equal(data.prompt.status, 'unavailable');
  assert.match(data.prompt.instruction, /Take a screenshot/);
  assert.ok(!result.content.some(item => item.type === 'image'));
});
test('observe_device rejects non-boolean include_image', async t => {
  const f = await fixture(t);
  const result = await f.call('observe_device', { include_image: 'false' });
  assert.equal(result.isError, true);
});
