#!/usr/bin/env node
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { access } from 'node:fs/promises';
import { join } from 'node:path';
import { root, idevice } from '../src/config.mjs';

const execute = promisify(execFile);
const { stdout } = await execute('python3', [join(root, 'native/devices.py')], { timeout: 8000 });
const ids = [...new Set(JSON.parse(stdout).map(d => d.id).filter(Boolean))];
const selected = process.argv[2] ?? (ids.length === 1 ? ids[0] : undefined);
if (!selected || !ids.includes(selected)) throw new Error('Connect one unlocked, trusted iPhone, or pass a connected device id.');
const call = async args => execute(idevice, ['--udid', selected, ...args], { timeout: 120000, maxBuffer: 8 * 1024 * 1024 });
const services = async () => (await call(['remotexpc'])).stdout;
if ((await services()).includes('com.apple.coredevice.displayservice')) {
  console.log('Device display service is already available.');
} else {
  const restore = '/Library/Developer/DeveloperDiskImages/iOS_DDI/Restore';
  await access(join(restore, 'BuildManifest.plist'))
    .catch(() => { throw new Error('Apple DeveloperDiskImages are missing. Install the compatible Apple developer support files before running this command.'); });
  console.log('Installing the local Apple-signed developer disk image on the selected device…');
  const result = await call(['cryptexd', 'install-ddi', restore]);
  if (!/installed com\.apple\.MobileAsset\.DDI|is already installed/.test(result.stdout)) throw new Error('The device did not confirm installation.');
  if (!(await services()).includes('com.apple.coredevice.displayservice')) throw new Error('The image is installed, but displayservice is still unavailable. Check image compatibility and device Developer settings.');
  console.log('Developer disk image installed; the device now exposes displayservice.');
}
