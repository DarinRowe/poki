import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import sharp from 'sharp';
import { fixture, value } from './fixture.mjs';

test('saving a screenshot keeps the original pixels and uses the filename format', async t => {
  const f = await fixture(t);
  await f.set({});
  const png = join(f.dir, 'native.png');
  const jpg = join(f.dir, 'native.jpg');
  const source = await readFile(f.image);
  assert.equal(value(await f.call('save_screenshot', { path: png })).bytes, source.length);
  assert.deepEqual(await readFile(png), source);
  const duplicate = await f.call('save_screenshot', { path: png });
  assert.equal(duplicate.isError, true);
  assert.deepEqual(await readFile(png), source);

  const saved = await f.call('save_screenshot', { path: jpg, lossless: true });
  assert.equal(saved.isError, undefined);
  const { format, width, height } = await sharp(jpg).metadata();
  assert.deepEqual({ format, width, height }, { format: 'jpeg', width: 100, height: 200 });
});
