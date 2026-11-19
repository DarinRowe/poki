import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseTesseractTSV, tesseractLanguages } from '../src/ocr.mjs';
import { promptWarning } from '../src/interaction.mjs';
import { Devices } from '../src/device.mjs';
import { stateDir } from '../src/config.mjs';
const header = 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext';
const fixture = header + '\n5\t1\t1\t1\t1\t1\t10\t20\t40\t15\t90\tClaude\n5\t1\t1\t1\t1\t2\t60\t20\t80\t15\t98\t最新消息\n';
test('TSV keeps Unicode line text, pixel bounds and normalized confidence', () => {
  assert.deepEqual(parseTesseractTSV(fixture), [{ text: 'Claude 最新消息', confidence: .94, x: 10, y: 20, width: 130, height: 15 }]);
  assert.deepEqual(parseTesseractTSV(header + '\n'), []);
  assert.throws(() => parseTesseractTSV('not TSV'), /Invalid/);
  assert.deepEqual(parseTesseractTSV(header + '\n5\t1\t1\t1\t1\t1\tNaN\t20\t40\t15\t90\tbad'), []);
});
test('configured Tesseract backend avoids the hung Vision binary and retains coordinate mapping', async () => {
  const before = process.env.POKI_OCR_BACKEND;
  process.env.POKI_OCR_BACKEND = 'tesseract';
  try {
    await mkdir(join(stateDir, 'frames'), { recursive: true });
    const phone = new Devices();
    const data = Buffer.from('fixture');
    phone.run = async (binary, args, timeout, input) => {
      assert.equal(binary, process.env.POKI_TESSERACT_BIN || 'tesseract');
      assert.deepEqual(args.slice(0, 2), ['stdin', 'stdout']);
      assert.equal(args.at(-1), 'tsv');
      assert.equal(timeout, 5000);
      assert.equal(input, data);
      return { stdout: fixture };
    };
    const rows = await phone.readOCR({ data });
    assert.equal(rows[0].label, 'Claude 最新消息');
    assert.deepEqual(rows[0].frame, { x: 10, y: 20, width: 130, height: 15 });
  } finally { if (before === undefined) delete process.env.POKI_OCR_BACKEND; else process.env.POKI_OCR_BACKEND = before; }
});

test('an unset OCR backend defaults to Tesseract', async () => {
  const before = process.env.POKI_OCR_BACKEND;
  delete process.env.POKI_OCR_BACKEND;
  try {
    await mkdir(join(stateDir, 'frames'), { recursive: true });
    const phone = new Devices();
    phone.run = async (binary, args) => {
      assert.equal(binary, process.env.POKI_TESSERACT_BIN || 'tesseract');
      assert.equal(args.at(-1), 'tsv');
      return { stdout: fixture };
    };
    assert.equal((await phone.readOCR({ data: Buffer.from('fixture') }))[0].label, 'Claude 最新消息');
  } finally {
    if (before !== undefined) process.env.POKI_OCR_BACKEND = before;
  }
});

test('spaced Chinese OCR text still triggers the paste prompt warning', () => {
  assert.deepEqual(promptWarning([{ text: '允 许 粘 贴' }]), { kind: 'paste' });
});

test('Tesseract discovers installed Chinese packs and respects an explicit language override', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'poki-tess-langs-'));
  t.after(() => rm(dir, { recursive: true }));
  const binary = join(dir, 'tesseract');
  await writeFile(binary, "#!/bin/sh\nprintf '%s\\n' 'List of available languages (4):' chi_sim eng osd chi_tra\n", { mode: 0o700 });
  assert.equal(await tesseractLanguages(binary), 'eng+chi_sim+chi_tra');
  assert.equal(await tesseractLanguages(binary, undefined, 'fra'), 'fra');
});
