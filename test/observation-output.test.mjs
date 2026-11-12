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

// Issue #60: JD's results page names its search box and four tabs; the products under them are drawn
// without accessibility elements and are only in the screenshot.
test('a tree that names only the top of the screen gets the screenshot text it left out', { timeout: 30000 }, async t => {
  const named = (role, label, x, y, width, height) => ({ role, label, frame: { x, y, width, height } });
  const seen = (text, x, y, width, height) => ({ text, x, y, width, height });
  const header = [['StaticText', '力矩扳手', 10, 4, 80, 16], ['Button', '综合', 0, 24, 25, 16], ['Button', '视频', 25, 24, 25, 16], ['Button', '直播', 50, 24, 25, 16], ['Button', '用户', 75, 24, 25, 16]];
  const products = [['2-20Nm 预置扭力扳手', 5, 60, 90, 14], ['¥89', 5, 78, 30, 14], ['加入购物车', 50, 96, 45, 16]];
  const state = { elements: header.map(e => named(...e)), ocrElements: [...header.map(([, ...e]) => seen(...e)), ...products.map(e => seen(...e))] };
  const f = await fixture(t);
  await f.set(state);
  const listed = value(await f.call('list_elements'));
  assert.deepEqual(listed.elements.map(e => [e.label, e.source]), [...header.map(e => [e[1], undefined]), ...products.map(e => [e[0], 'ocr'])]);
  assert.equal(value(await f.call('list_elements', { source: 'accessibility' })).elements.length, 5);
  const cua = await fixture(t, { toolsProfile: 'cua' });
  await cua.set(state);
  const looked = (await cua.call('look')).content[0].text;
  assert.match(looked, /, accessibility \+ ocr\)/);
  assert.deepEqual(looked.split('\n').filter(line => /^[ +]\d+ /.test(line)).map(line => line.match(/"(.*)"/)[1]), [...header.map(e => e[1]), ...products.map(e => e[0])]);
});

test('a Tesseract process timeout leaves the screenshot and reports prompt OCR unavailable', async t => {
  const f = await fixture(t);
  await f.set({ ocrDelayMs: 7000 });
  const result = await f.call('take_screenshot');
  assert.ok(!result.isError);
  assert.ok(result.content.some(item => item.type === 'image' && item.mimeType === 'image/jpeg'));
  assert.ok(result.content.some(item => item.text?.includes('Prompt check: {"status":"unavailable"')));
});

test('numeric_region returns OCR boxes in the original screen coordinates', async t => {
  const f = await fixture(t);
  await f.set({ ocrLabel: '12:34' });
  const region = { x: 8, y: 20, width: 70, height: 55 };
  const result = value(await f.call('list_elements', { numeric_region: region }));
  assert.equal(result.source, 'ocr');
  assert.equal(result.elements[0].text, '12:34');
  assert.deepEqual(result.elements[0].frame, { x: 18, y: 30, width: 40, height: 20 });
  const outside = await f.call('list_elements', { numeric_region: { ...region, width: 101 } });
  assert.equal(outside.isError, true);
  assert.match(outside.content[0].text, /inside the captured screen/);
});

test('image fallback serves visible AX without attaching an image or invoking OCR', async t => {
  const f = await fixture(t);
  const first = await f.call('observe_device', { fallback: 'image', ax_hint: 'first' });
  assert.equal(value(first).source, 'accessibility');
  assert.equal(value(first).elements[0].label, 'First');
  assert.equal(value(first).prompt.source, 'accessibility');
  assert.ok(!first.content.some(item => item.type === 'image'));
  const captures = (await f.events()).filter(event => event.args?.includes('screenshot')).length;
  const second = await f.call('observe_device', { fallback: 'image' });
  assert.equal(value(second).source, 'accessibility');
  const events = await f.events();
  assert.equal(events.filter(event => event.args?.includes('screenshot')).length, captures);
  assert.equal(events.filter(event => event.tool === 'ocr').length, 0);
});

test('image fallback supplies a screenshot when AX misses the target or fails', async t => {
  const f = await fixture(t);
  for (const [state, reason] of [[{}, 'ax_hint_missing'], [{ axUnavailable: true }, 'accessibility_unavailable']]) {
    await f.set(state);
    const result = await f.call('observe_device', { fallback: 'image', ax_hint: 'canvas text' });
    const observation = value(result);
    assert.equal(observation.source, 'image');
    assert.equal(observation.fallback_reason, reason);
    assert.equal(observation.prompt.status, 'unavailable');
    assert.deepEqual(observation.elements, []);
    assert.ok(result.content.some(item => item.type === 'image' && item.mimeType === 'image/png'));
  }
  const events = await f.events();
  assert.equal(events.filter(event => event.args?.includes('screenshot')).length, 2);
  assert.equal(events.filter(event => event.tool === 'ocr').length, 0);
});

test('an AX read deadline still yields the screenshot in image fallback mode', async t => {
  const f = await fixture(t);
  await f.set({ axDelayMs: 6000 });
  const result = await f.call('observe_device', { fallback: 'image' });
  assert.equal(value(result).fallback_reason, 'accessibility_timeout');
  assert.ok(result.content.some(item => item.type === 'image'));
  assert.equal((await f.events()).filter(event => event.tool === 'ocr').length, 0);
});

test('hybrid routes known visible text through AX, OCR, then a single image', async t => {
  const f = await fixture(t);
  await f.set({ ocrLabel: 'Canvas text' });
  const read = ax_hint => f.call('observe_device', { fallback: 'hybrid', ax_hint });
  const ax = await read('first');
  assert.equal(value(ax).source, 'accessibility');
  assert.equal((await f.events()).filter(event => event.tool === 'ocr').length, 0);
  const ocr = await read('canvas text');
  assert.equal(value(ocr).source, 'ocr');
  assert.equal(value(ocr).fallback_reason, 'ax_hint_missing');
  assert.equal(value(ocr).observation.structure_source, 'ocr');
  assert.equal(value(ocr).elements[0].label, 'Canvas text');
  assert.ok(value(ocr).elements[0].ref);
  assert.equal(ocr.content.some(item => item.type === 'image'), false);
  await f.set({ ocrLabel: 'Canvas text', ocrConfidence: 40 });
  const image = await read('canvas text');
  assert.equal(value(image).fallback_reason, 'ocr_uncertain');
  assert.deepEqual(value(image).elements, []);
  assert.equal(image.content.filter(item => item.type === 'image').length, 1);
  assert.equal(value(await read('another target')).fallback_reason, 'ocr_hint_missing');
});

test('hybrid returns one image after the OCR deadline and can read the next frame', async t => {
  const f = await fixture(t);
  await f.set({ axUnavailable: true, ocrDelayMs: 7000, ocrLabel: 'Canvas text' });
  const read = () => f.call('observe_device', { fallback: 'hybrid', ax_hint: 'canvas text' });
  const result = await read();
  assert.equal(value(result).fallback_reason, 'ocr_timeout');
  assert.equal(result.content.filter(item => item.type === 'image').length, 1);
  assert.equal((await f.events()).filter(event => event.args?.includes('screenshot')).length, 1);
  await f.set({ axUnavailable: true, ocrLabel: 'Canvas text' });
  assert.equal(value(await read()).source, 'ocr');
});

test('explicit hybrid visual request goes straight to the screenshot', async t => {
  const f = await fixture(t);
  const result = await f.call('observe_device', { fallback: 'hybrid', require_visual: true });
  assert.equal(value(result).fallback_reason, 'visual_requested');
  assert.equal(value(result).prompt.status, 'unavailable');
  assert.equal(result.content.filter(item => item.type === 'image').length, 1);
  assert.ok(!(await f.events()).some(event => event.tool === 'ocr' || ['ax', 'ax_tree'].includes(event.op)));
  const invalid = await f.call('observe_device', { fallback: 'image', require_visual: true });
  assert.equal(invalid.isError, true);
});

test('hybrid can try local OCR without repeating an insufficient AX read', async t => {
  const f = await fixture(t);
  await f.set({ ocrLabel: 'Unknown page text' });
  const result = await f.call('observe_device', { fallback: 'hybrid', skip_ax: true });
  assert.equal(value(result).source, 'ocr');
  assert.equal(value(result).fallback_reason, 'ocr_requested');
  assert.ok(!(await f.events()).some(event => ['ax', 'ax_tree'].includes(event.op)));
});
