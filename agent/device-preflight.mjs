import { access, stat } from 'node:fs/promises';
import { constants } from 'node:fs';
import { idevice } from '../src/config.mjs';

export async function checkDeviceTools() {
  try {
    await access(idevice, constants.X_OK);
    if (!(await stat(idevice)).isFile()) throw new Error('Not an executable file');
  } catch {
    throw Object.assign(new Error('Poki cannot read the phone: idevice-tools is missing or not executable. Run ./bin/setup in this checkout, or set IDEVICE_TOOLS to the installed executable, then restart the channel.'), { code: 'device_setup' });
  }
}
