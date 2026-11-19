import assert from 'node:assert/strict';
import test from 'node:test';
import { addControl, setSlider } from '../src/controls.mjs';
import { fixture, value } from './fixture.mjs';

const foreground = { pid: 37 };
const slider = (label, value, frame, object_id = 'slider') => ({ role: 'Adjustable', label, value, frame, object_id });
const tall = { x: 100, y: 200, width: 60, height: 220 };
const wide = { x: 40, y: 60, width: 240, height: 30 };
const screen = (elements, app = foreground) => ({ foreground: app, elements });
const context = (...screens) => {
  const inputs = [];
  return { inputs, settle: async () => {}, structure: async () => screens.shift(), input: async input => {
    inputs.push(input);
    return { sent: true };
  } };
};

test('sliders use fresh bounds and verify both system and app percentages', async () => {
  const phone = context(screen([slider('Brightness', '20%', tall)]), screen([slider('Brightness', '51%', tall)]));
  const system = await setSlider(phone, { text: 'Brightness', percent: 50 }, () => false);
  assert.equal(system.value_verified, true);
  assert.equal(system.actual_percent, 51);
  assert.ok(phone.inputs[0].y2 < phone.inputs[0].y1);
  assert.equal(phone.inputs[0].x1, 130);

  const app = { bundle_id: 'example.editor' };
  const editor = context(screen([slider('Opacity', '80%', wide)], app), screen([slider('Opacity', '30%', wide)], app));
  assert.equal((await setSlider(editor, { text: 'Opacity', percent: 30 }, () => false)).value_verified, true);
  assert.ok(editor.inputs[0].x2 < editor.inputs[0].x1);
});

test('rounded readback inside tolerance does not send a correction', async () => {
  const phone = context(screen([slider('Brightness', '0%', tall)]), screen([slider('Brightness', '33%', tall)]));
  const result = await setSlider(phone, { text: 'Brightness', percent: 30 }, () => false);
  assert.ok(result.value_verified);
  assert.equal(result.actual_percent, 33);
  assert.equal(phone.inputs.length, 1);
});

test('setting an already satisfied or ambiguous slider sends nothing', async () => {
  const same = context(screen([slider('Volume', '40%', tall)]));
  assert.equal((await setSlider(same, { text: 'Volume', percent: 40 }, () => false)).already_set, true);
  assert.equal(same.inputs.length, 0);
  const two = context(screen([slider('Volume', '20%', tall), slider('Volume', '80%', wide)]));
  assert.equal((await setSlider(two, { text: 'Volume', percent: 40 }, () => false)).reason, 'slider_unconfirmed');
  assert.equal(two.inputs.length, 0);
});

test('slider changes stop on lost readback, replaced control or unchanged value', async () => {
  for (const after of [screen([]), screen([slider('Volume', '40%', tall, 'new')]), screen([slider('Volume', '20%', tall)])]) {
    const phone = context(screen([slider('Volume', '20%', tall)]), after);
    const result = await setSlider(phone, { text: 'Volume', percent: 40 }, () => false);
    assert.equal(result.value_verified, false);
    assert.equal(phone.inputs.length, 1);
  }
});

const button = (label, value) => ({ type: 'Button', label, value, frame: wide });
const gallery = (...controls) => screen([
  { type: 'Application', label: ' ', frame: { x: 0, y: 0, width: 100, height: 200 } },
  { type: 'SearchField', frame: { x: 8, y: 27, width: 80, height: 24 } }, button('Sheet Grabber', 'Expanded'), ...controls,
]);

test('gallery add uses an exact candidate, can search once, and verifies the installed item', async () => {
  const phone = context(gallery(button('Alarm', 'Control')), gallery(button('Low Power Mode', 'Control')),
    screen([button('Low Power Mode', 'Off')]));
  const result = await addControl(phone, { text: 'Low Power Mode' }, async args => {
    assert.deepEqual(args, { text: 'Low Power Mode', submit: false });
    return { sent: true, text_verified: true };
  });
  assert.deepEqual(result, { sent: true, added: true, verified: true });
  assert.equal(phone.inputs.length, 1);
});

test('gallery add rejects ordinary app search and leaves unknown delivery to inspection', async () => {
  const app = context(screen(gallery(button('Dark Mode', 'Control')).elements, { bundle_id: 'example.catalog' }));
  assert.equal((await addControl(app, { text: 'Dark Mode' }, assert.fail)).reason, 'control_gallery_unconfirmed');
  assert.equal(app.inputs.length, 0);
  const phone = context(gallery(button('Dark Mode', 'Control')), screen([]));
  const result = await addControl(phone, { text: 'Dark Mode' }, assert.fail);
  assert.equal(result.outcome, 'unknown');
  assert.equal(phone.inputs.length, 1);
});

test('a padded slider uses the observed inner track and rejects endpoints outside its frame', async () => {
  const track = { min: { x: 65, y: 73 }, max: { x: 250, y: 73 } };
  const before = screen([slider('Amount', '0%', wide)]);
  const phone = context(before, screen([slider('Amount', '50%', wide)]));
  assert.ok((await setSlider(phone, { text: 'Amount', percent: 50, track }, () => false)).value_verified);
  assert.equal(phone.inputs[0].x1, 65);
  const invalid = context(before);
  assert.equal((await setSlider(invalid, { text: 'Amount', percent: 50, track: { ...track, min: { x: 10, y: 73 } } },
    () => false)).reason, 'slider_track_outside_control');
  assert.equal(invalid.inputs.length, 0);
});

test('the MCP add tool returns inspection evidence when the editor cannot verify the tile', async t => {
  const f = await fixture(t);
  await f.set({ bundleId: 'com.apple.springboard', elements: gallery({ ...button('Text Size', 'Control'), frame: { x: 10, y: 75, width: 45, height: 26 } }).elements,
    afterInput: { elements: null, label: 'Editor' } });
  const response = await f.call('add_control', { text: 'Text Size' });
  assert.equal(response.isError, true);
  assert.equal(value(response).reason, 'control_add_unverified');
  assert.ok(response.content.some(item => item.type === 'image'));
});
