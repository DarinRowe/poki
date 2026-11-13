import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { Devices } from '../src/device.mjs';
import { whatMoved } from '../src/interaction.mjs';

// A page invented for these tests: a header, two buttons and a sideways row of chips ("Recent")
// that pages under a drag. Drawn as blocks, so pixels change exactly when the screen does.
const W = 200, H = 400, app = { pid: 501, bundle_id: 'local.rows' };
const el = (role, label, x, y, width, height) => ({ role, type: role, label, x, y, width, height });

class RowPhone extends Devices {
  offset = 0; drags = []; taps = 0; axReads = 0; captures = 0; dragError; recognized = [];
  constructor() { super(); this.size = { device: 'phone-1', width: W, height: H }; }
  screen() {
    return { foreground: app, elements: [el('StaticText', 'Accounts', 10, 40, 100, 20), el('Button', 'Entries', 10, 100, 180, 40), el('Button', 'Settings', 10, 150, 180, 40),
      el('CollectionView', 'Recent', 0, 200, 200, 60), ...[1, 2, 3, 4, 5, 6].map(n => el('Cell', `Chip ${n}`, 10 + (n - 1) * 70 + this.offset, 210, 60, 40)).filter(e => e.x < W && e.x + e.width > 0)] };
  }
  async inventory() { return [{ id: 'phone-1', kind: 'physical', name: 'Test Phone', state: 'Booted' }]; }
  async bridge(request) {
    if (request.op === 'ax') { this.axReads++; return this.screen(); }
    if (request.op === 'tap') this.taps++;
    if (request.op === 'drag') {
      this.drags.push(request);
      if (this.dragError) return this.dragError;
      const [x1, y1, x2] = [request.x1 / 65535 * (W - 1), request.y1 / 65535 * (H - 1), request.x2 / 65535 * (W - 1)];
      if (y1 >= 200 && y1 <= 260) this.offset = Math.max(-280, Math.min(0, this.offset + Math.round(x2 - x1)));
    }
    return { sent: true, screen_change_verified: false };
  }
  async captureFrame() {
    this.captures++;
    const blocks = await Promise.all(this.screen().elements.map(async e => ({ input: await sharp({ create: { width: Math.max(4, Math.min(e.width, W - Math.max(0, e.x))), height: e.height, channels: 3, background: { r: e.label.length * 9 % 200, g: 90, b: 90 } } }).png().toBuffer(), left: Math.max(0, e.x), top: e.y })));
    const data = await sharp({ create: { width: W, height: H, channels: 3, background: 'white' } }).composite(blocks).png().toBuffer();
    const now = new Date().toISOString();
    this.frame = { id: String(Math.random()), device: 'phone-1', revision: this.coordinator.revision('phone-1'), width: W, height: H, scale: 1, data, original: data, at: Date.now(), capture_started_at: now, capture_completed_at: now };
    return this.frame;
  }
  async ocr() { return this.recognized; }
}
const body = result => JSON.parse(result.content.find(block => block.type === 'text').text);

test('quick scrolling returns a single unverified AX window with duplicates and no tap refs', async () => {
  class DuplicatePhone extends RowPhone {
    screen() {
      return { foreground: app, elements: [el('Cell', 'Entry', 10, 80, 180, 30), el('Cell', 'Entry', 10, 120, 180, 30)] };
    }
  }
  const phone = new DuplicatePhone();
  const result = await phone.call('batch_commands', { commands: [
    { tool: 'scroll', arguments: { direction: 'down', observe: 'quick', return_observation: true } },
  ] });
  const action = JSON.parse(result.content[1].text);
  const summary = JSON.parse(result.content.at(-1).text);
  assert.equal(action.sent, true);
  assert.equal(action.screen_change, 'unknown');
  assert.deepEqual(summary.screen, action.screen);
  assert.equal(action.screen.screen_stable, false);
  assert.deepEqual(action.screen.elements.map(e => [e.label, e.frame[1], e.ref]), [['Entry', 80, undefined], ['Entry', 120, undefined]]);
  assert.equal(action.post_action_observation, undefined);
  assert.equal(phone.axReads, 1);
  assert.equal(phone.drags.length, 1);
});

test('an uncertain quick swipe is neither observed nor replayed', async () => {
  const phone = new RowPhone();
  phone.dragError = { isError: true, outcome: 'unknown', stop_reason: 'unknown' };
  const result = await phone.call('swipe', { from_x: 80, from_y: 300, to_x: 80, to_y: 150, observe: 'quick' });
  assert.equal(result.isError, true);
  assert.equal(body(result).outcome, 'unknown');
  assert.equal(phone.axReads, 0);
  assert.equal(phone.drags.length, 1);
});

test('a batch reports an AX-only tap miss from the lookup tree without reading again', async () => {
  const phone = new RowPhone();
  const result = await phone.call('batch_commands', { commands: [
    { tool: 'tap_text', arguments: { text: 'Chip 6', exact: true, source: 'accessibility' } },
    { tool: 'tap_text', arguments: { text: 'Entries', exact: true } },
  ] });
  const summary = JSON.parse(result.content.at(-1).text);
  assert.equal(result.isError, true);
  assert.equal(summary.recovery.outcome, 'not_sent');
  assert.equal(summary.screen.screen_stable, false);
  assert.ok(summary.screen.text.includes('Cell: Chip 1'));
  assert.equal(summary.recovery.unattempted_steps.length, 1);
  assert.equal(phone.axReads, 1);
  assert.equal(phone.captures, 0);
  assert.equal(phone.taps, 0);
});

test('the tap after scroll_to reuses its AX sample and still checks motion', async () => {
  class MovingRowPhone extends RowPhone {
    positions = [];
    async bridge(request) {
      if (request.op === 'ax' && this.drags.length && !this.taps) {
        // The first post-drag tree still sees the row sliding.
        if (this.positions.length === 1) this.offset -= 12;
        this.positions.push(this.offset);
      }
      if (request.op === 'tap') {
        const x = Math.round(request.x / 65535 * (W - 1));
        assert.equal(x, 320 + this.offset);
      }
      return super.bridge(request);
    }
  }
  const phone = new MovingRowPhone();
  const result = await phone.call('batch_commands', { commands: [
    { tool: 'scroll_to', arguments: { text: 'Chip 5', exact: true, source: 'accessibility', direction: 'right', container: 'Recent' } },
    { tool: 'tap_text', arguments: { text: 'Chip 5', exact: true } },
  ] });
  assert.equal(result.isError, undefined, JSON.stringify(result.content));
  assert.equal(phone.drags.length, 1);
  assert.equal(phone.taps, 1);
  assert.equal(phone.positions.length, 3);
  assert.notEqual(phone.positions[0], phone.positions[1]);
  assert.equal(phone.positions[1], phone.positions[2]);
  const stages = result._meta.timing.stages;
  const pre = stages.find(s => s.phase === 'pre_action_ax');
  assert.ok(pre);
  assert.ok(!stages.some(s => s.parent === pre.id && s.phase === 'accessibility'));
});

test('a vertical search followed by a tap on the same label pages with a held release', async () => {
  class ListPhone extends RowPhone {
    screen() {
      const label = this.drags.length ? 'Details' : 'Overview';
      return { foreground: app, elements: [el('Button', label, 10, 150, 180, 40)] };
    }
  }
  const phone = new ListPhone();
  const result = await phone.call('batch_commands', { commands: [
    { tool: 'scroll_to', arguments: { text: 'Details', exact: true, source: 'accessibility' } },
    { tool: 'tap_text', arguments: { text: 'Details', exact: true } },
  ] });
  assert.equal(result.isError, undefined, JSON.stringify(result.content));
  assert.equal(phone.drags.length, 1);
  assert.ok(phone.drags[0].end_hold_ms > 0);
  assert.equal(phone.taps, 1);
});

test('scroll_to stops after a drag with uncertain delivery', async () => {
  const phone = new RowPhone();
  phone.dragError = { isError: true, outcome: 'unknown', stop_reason: 'unknown' };
  const result = await phone.call('scroll_to', { text: 'Chip 6', direction: 'right', container: 'Recent' });
  assert.equal(result.isError, true);
  assert.equal(body(result).outcome, 'unknown');
  assert.equal(phone.drags.length, 1);
});

test('an AX-only search can find visible text without capturing or scrolling', async () => {
  const phone = new RowPhone();
  const found = body(await phone.call('scroll_to', { text: 'Chip 1', source: 'accessibility', exact: true }));
  assert.equal(found.found, true);
  assert.equal(found.elements[0].label, 'Chip 1');
  assert.equal(phone.captures, 0);
  assert.equal(phone.drags.length, 0);
});

test('default search still finds visual text omitted from AX', async () => {
  const phone = new RowPhone();
  phone.recognized = [el('StaticText', 'Canvas heading', 10, 50, 100, 20)];
  const found = body(await phone.call('scroll_to', { text: 'Canvas heading', exact: true }));
  assert.equal(found.found, true);
  assert.equal(found.source, 'ocr');
  assert.equal(phone.captures, 1);
  assert.equal(phone.drags.length, 0);
});

test('a one-page scroll inside a named row moves only that row, without coasting, and says which container moved', { timeout: 30000 }, async () => {
  const phone = new RowPhone();
  const single = body(await phone.call('scroll', { direction: 'right', container: 'Recent', pages: 1 }));
  const drag = phone.drags.at(-1);
  assert.ok(drag.end_hold_ms > 0, 'held before lifting, so the row does not coast');
  const y = drag.y1 / 65535 * (H - 1);
  assert.ok(y >= 200 && y <= 260, `dragged inside the row, at y ${y}`);
  assert.ok(drag.x1 > drag.x2, 'the finger moves left to reveal what is to the right');
  assert.equal(single.moved?.container, 'Recent', JSON.stringify(single));
  assert.ok(single.moved.shift.x < -100 && single.moved.shift.y === 0, JSON.stringify(single.moved));
  const found = body(await phone.call('scroll_to', { text: 'Chip 6', direction: 'right', container: 'Recent' }));
  assert.equal(found.found, true, JSON.stringify(found));
  assert.ok(phone.drags.at(-1).end_hold_ms > 0, 'scroll_to pages sideways lists');
});

test('whatMoved names the container whose items shifted together', () => {
  const row = el('CollectionView', 'Media Types', 0, 300, 390, 120);
  const before = [row, el('StaticText', 'Header', 10, 40, 100, 20), el('Cell', 'Videos', 10, 310, 100, 100), el('Cell', 'Selfies', 120, 310, 100, 100), el('Cell', 'Live', 230, 310, 100, 100)];
  const after = [row, el('StaticText', 'Header', 10, 40, 100, 20), el('Cell', 'Selfies', 10, 310, 100, 100), el('Cell', 'Live', 120, 310, 100, 100), el('Cell', 'Portrait', 230, 310, 100, 100)];
  assert.deepEqual(whatMoved(before, after), { container: 'Media Types', frame: [0, 300, 390, 120], shift: { x: -110, y: 0 }, items_moved: 2, appeared: 1 });
  assert.equal(whatMoved(before, before), null);
});
