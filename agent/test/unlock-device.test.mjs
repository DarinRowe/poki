import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { unlockDevice } from '../unlock-device.mjs';

test('Unlock host sends the configured passcode only on stdin and hides helper errors', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'poki-unlock-'));
  const before = { passcode: process.env.POKI_IPHONE_PASSCODE, native: process.env.POKI_UNLOCK_NATIVE };
  t.after(async () => {
    for (const [name, value] of [['POKI_IPHONE_PASSCODE', before.passcode], ['POKI_UNLOCK_NATIVE', before.native]]) {
      if (value === undefined) delete process.env[name]; else process.env[name] = value;
    }
    await rm(dir, { recursive: true, force: true });
  });
  delete process.env.POKI_IPHONE_PASSCODE;
  await assert.rejects(unlockDevice('synthetic-device'), /No iPhone passcode/);
  const helper = join(dir, 'fake-native');
  process.env.POKI_UNLOCK_NATIVE = helper;
  process.env.POKI_IPHONE_PASSCODE = '813790';
  await writeFile(helper, '#!/usr/bin/env python3\nimport sys,os,json\npin=sys.stdin.read()\nassert pin=="813790"\nassert pin not in " ".join(sys.argv)\nassert "POKI_IPHONE_PASSCODE" not in os.environ\nprint(json.dumps({"input_sent":True}))\n', { mode: 0o700 });
  await unlockDevice('synthetic-device');
  await writeFile(helper, '#!/usr/bin/env python3\nimport sys\nprint(sys.stdin.read(),file=sys.stderr)\nsys.exit(1)\n');
  await assert.rejects(unlockDevice('synthetic-device'), error => !error.message.includes('813790') && /did not complete/.test(error.message));
});
