#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { readFile, stat } from 'node:fs/promises';
import { homedir } from 'node:os';
import { resolve, join } from 'node:path';

try {
  const { values } = parseArgs({ options: {
    'config-dir': { type: 'string', default: join(homedir(), '.config/poki-agent/imessage') },
    check: { type: 'boolean' }, help: { type: 'boolean', short: 'h' },
  } });
  if (values.help) {
    console.log('Usage: node bin/poki-imessage.mjs [--config-dir <private directory>] [--check]\n--check authenticates and reads only; no task or reply is sent.');
  } else {
    const directory = resolve(values['config-dir']);
    const path = join(directory, 'connection.json');
    if ((await stat(path)).mode & 0o077) throw new Error('Private connection file must have mode 600.');
    const connection = JSON.parse(await readFile(path, 'utf8'));
    if (typeof connection.url !== 'string' || typeof connection.password !== 'string' || !connection.password) {
      throw new Error('Invalid connection configuration.');
    }
    process.env.BLUEBUBBLES_URL = connection.url;
    process.env.BLUEBUBBLES_PASSWORD = connection.password;
    process.argv = [process.execPath, 'agent/imessage.mjs', '--config', join(directory, 'imessage.json'),
      '--state', join(directory, 'state'), ...(values.check ? ['--check'] : [])];
    await import('../agent/imessage.mjs');
  }
} catch {
  console.error('Cannot load private iMessage settings. Check the configuration directory, JSON fields and file permissions.');
  process.exitCode = 1;
}
