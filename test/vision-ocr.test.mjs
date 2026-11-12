import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter, once } from 'node:events';
import { PassThrough } from 'node:stream';
import { VisionOCR } from '../src/vision-ocr.mjs';

const image = Buffer.from('frame');
const descriptor = { key: 'phone', pixels: Buffer.from([5, 10, 15, 20]) };
const secondPage = { key: 'phone', pixels: Buffer.from([100, 15, 95, 10]) };
const row = { text: 'Settings', x: 5, y: 5, width: 50, height: 16, confidence: 1 };

function fixture(t, timeouts = {}) {
  const children = [];
  const ocr = new VisionOCR({ timeouts, start() {
    const child = new EventEmitter();
    child.stdin = new PassThrough();
    child.stdout = new PassThrough();
    child.requests = [];
    child.stdin.on('data', chunk => child.requests.push(JSON.parse(chunk)));
    child.reply = message => child.stdout.write(JSON.stringify(message) + '\n');
    child.kill = () => {
      if (child.killed) return;
      child.killed = true;
      queueMicrotask(() => child.emit('close'));
    };
    children.push(child);
    return child;
  } });
  t.after(() => ocr.close());
  return { ocr, children };
}

function recognize(ocr, options = {}) {
  return ocr.recognize(image, { descriptor, ...options });
}

function reply(child, rows = [row]) {
  const request = child.requests.shift();
  assert.ok(request);
  child.reply({ id: request.id, rows });
  return request;
}

function qualify(ocr, child, options) {
  assert.equal(recognize(ocr, options), undefined);
  reply(child);
  assert.equal(recognize(ocr, options), undefined);
  reply(child);
}

test('real page probes stay in the background until a similar page has two fast replies', async t => {
  const { ocr, children } = fixture(t);
  assert.equal(children.length, 0);
  assert.equal(recognize(ocr), undefined);
  assert.equal(recognize(ocr, { descriptor: secondPage }), undefined);
  const [child] = children;
  assert.equal(child.requests.length, 1);
  const first = reply(child);
  assert.equal(Buffer.from(first.image, 'base64').toString(), 'frame');
  assert.equal(recognize(ocr), undefined);
  reply(child);
  const similar = { key: 'phone', pixels: Buffer.from([6, 13, 17, 20]) };
  const result = recognize(ocr, { descriptor: similar });
  const request = child.requests[0];
  child.reply({ id: request.id + 1, rows: [row] });
  reply(child, []);
  assert.deepEqual(await result, []);
  assert.equal(recognize(ocr, { descriptor: secondPage }), undefined);
  reply(child);
  assert.equal(recognize(ocr, { descriptor: secondPage }), undefined);
  reply(child);
  const other = recognize(ocr, { descriptor: secondPage });
  reply(child);
  assert.deepEqual(await other, [row]);
  await ocr.close();
  assert.ok(child.killed);
  assert.equal(recognize(ocr), undefined);
  assert.equal(children.length, 1);
});

test('a slow foreground reply falls back and demotes only its page', async t => {
  const { ocr, children } = fixture(t, { reply: 15, hardReply: 500 });
  recognize(ocr);
  const [child] = children;
  reply(child);
  recognize(ocr);
  reply(child);
  qualify(ocr, child, { descriptor: secondPage });
  assert.equal(await recognize(ocr), undefined);
  assert.equal(recognize(ocr), undefined);
  assert.equal(child.requests.length, 1);
  reply(child);
  assert.equal(recognize(ocr), undefined);
  assert.equal(child.requests.length, 0);
  const other = recognize(ocr, { descriptor: secondPage });
  reply(child);
  assert.deepEqual(await other, [row]);
});

test('a hung foreground recognition is reaped after the hard deadline', async t => {
  const { ocr, children } = fixture(t, { reply: 15, hardReply: 55 });
  recognize(ocr);
  const [child] = children;
  reply(child);
  recognize(ocr);
  reply(child);
  const closed = once(child, 'close');
  assert.equal(await recognize(ocr), undefined);
  assert.equal(child.killed, undefined);
  const watchdog = setTimeout(() => {}, 100);
  try { await closed; } finally { clearTimeout(watchdog); }
  assert.equal(recognize(ocr), undefined);
  assert.equal(children.length, 1);
});

test('caller cancellation keeps the shared worker and discards the late reply', async t => {
  const { ocr, children } = fixture(t);
  recognize(ocr);
  const [child] = children;
  reply(child);
  recognize(ocr);
  reply(child);
  const controller = new AbortController();
  const result = recognize(ocr, { signal: controller.signal });
  controller.abort();
  await assert.rejects(result, { name: 'AbortError' });
  assert.equal(recognize(ocr), undefined);
  reply(child);
  const next = recognize(ocr);
  reply(child);
  assert.deepEqual(await next, [row]);
  assert.equal(children.length, 1);
});

test('an unused worker exits and critical pressure interrupts a busy worker', async t => {
  const { ocr, children } = fixture(t, { idle: 20 });
  recognize(ocr);
  const [first] = children;
  reply(first);
  const watchdog = setTimeout(() => {}, 100);
  try { await once(first, 'close'); } finally { clearTimeout(watchdog); }
  recognize(ocr);
  const second = children[1];
  reply(second);
  recognize(ocr);
  reply(second);
  const busy = recognize(ocr);
  second.reply({ pressure: 'critical' });
  assert.equal(await busy, undefined);
  assert.equal(second.killed, true);
});

test('warning pressure lets an active recognition finish and then retires the worker', async t => {
  const { ocr, children } = fixture(t);
  recognize(ocr);
  const [child] = children;
  reply(child);
  recognize(ocr);
  reply(child);
  const result = recognize(ocr);
  child.reply({ pressure: 'warning' });
  assert.equal(child.killed, undefined);
  reply(child);
  assert.deepEqual(await result, [row]);
  assert.equal(child.killed, true);
});

test('abandoned warmup reaps the child without waiting for the hard warmup limit', async t => {
  const { ocr, children } = fixture(t, { warmupIdle: 20, warmup: 10000 });
  recognize(ocr);
  const [child] = children;
  const watchdog = setTimeout(() => {}, 100);
  try { await once(child, 'close'); } finally { clearTimeout(watchdog); }
  assert.equal(child.killed, true);
});
