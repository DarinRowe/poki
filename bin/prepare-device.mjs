#!/usr/bin/env node
import { execFile } from 'node:child_process';
import { parseArgs, promisify } from 'node:util';
import { access } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { root, idevice } from '../src/config.mjs';

const fail = message => { console.error(message); process.exit(1); };
const execute = promisify(execFile);
const { values: options, positionals } = parseArgs({ allowPositionals: true, options: { image: { type: 'string' } } });
const { stdout } = await execute('python3', [join(root, 'native/devices.py')], { timeout: 8000 });
const ids = [...new Set(JSON.parse(stdout).map(d => d.id).filter(Boolean))];
const selected = positionals[0] ?? (ids.length === 1 ? ids[0] : undefined);
if (!selected || !ids.includes(selected)) fail('Connect one unlocked, trusted iPhone, or pass a connected device id.');
const call = async args => execute(idevice, ['--udid', selected, ...args], { timeout: 120000, maxBuffer: 8 * 1024 * 1024 });
const display = 'com.apple.coredevice.displayservice';
const hasDisplay = async () => (await call(['remotexpc'])).stdout.includes(display);
const newerImage = `Use the developer disk image of an Xcode release that supports this iOS version, or pass a newer Apple-signed Cryptex image: node bin/prepare-device.mjs ${selected} --image DIR.`;
const restart = 'Quit Xcode, restart the iPhone, reconnect it over USB, unlock it, and run this command again with Xcode closed.';
const installFailures = [
  [/BadBuildManifest/, () => `Its BuildManifest.plist has no build identity whose variant ends with "Developer Disk Image Cryptex", the only form the installer accepts. Older images, such as the one in Xcode 26.6 (17F113), use a variant containing "Cryptex Developer Disk Image" instead. ${newerImage}`],
  [/TSS server responded with non-success status \(([^)]*)\)/, detail => `Apple's signing server declined to personalize this image for this iPhone (${detail}). The image may be older than the builds Apple currently signs for this device. ${newerImage}`],
  [/\/System\/Developer \[17: File exists\]/, () => `Another developer disk image is already mounted at /System/Developer on the iPhone. ${restart}`],
];

if (await hasDisplay()) {
  console.log('Device display service is already available.');
} else {
  console.log(`The iPhone does not provide ${display}, which touch and text input need. Screenshots and accessibility work without it.`);
  const image = resolve(options.image ?? '/Library/Developer/DeveloperDiskImages/iOS_DDI/Restore');
  await access(join(image, 'BuildManifest.plist')).catch(() => fail(options.image
    ? `${image} has no BuildManifest.plist. Pass the directory that holds the image's BuildManifest.plist and its payloads.`
    : 'Apple DeveloperDiskImages are missing. Install the compatible Apple developer support files before running this command.'));
  console.log(`Installing the Apple-signed developer disk image from ${image} on the selected device…`);
  const result = await call(['cryptexd', 'install-ddi', image]).catch(error => {
    const output = `${error.stderr ?? ''}\n${error.stdout ?? ''}`;
    for (const [pattern, explain] of installFailures) {
      const match = output.match(pattern);
      if (match) fail(`Installing ${image} failed. ${explain(match[1])}`);
    }
    fail(`Installing ${image} failed: ${output.trim().split('\n').slice(-3).join(' ')}`);
  });
  if (!/installed com\.apple\.MobileAsset\.DDI|is already installed/.test(result.stdout)) fail('The device did not confirm installation.');
  if (!(await hasDisplay())) fail(`A developer disk image is installed, but it does not provide ${display}. The installed image may be older than this iOS version needs. ${newerImage} ${restart}`);
  console.log('Developer disk image installed; the device now exposes displayservice.');
}
