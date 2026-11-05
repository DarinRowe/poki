import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir, rename } from 'node:fs/promises';
import { join, dirname } from 'node:path';

export function channelURL(value, name) {
  let url;
  try { url = new URL(value); } catch { throw new Error(`Set ${name} to the server URL.`); }
  if (url.username || url.password || url.search || url.hash || url.pathname !== '/' ||
      !(url.protocol === 'https:' || url.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname))) {
    throw new Error(`${name} must use HTTPS or loopback HTTP, without credentials, a path or query parameters.`);
  }
  return url;
}

export class ChannelCursor {
  constructor(directory, channel, scope) {
    this.path = join(directory, `${channel}-${createHash('sha256').update(scope).digest('hex')}.json`);
  }

  async open() {
    const state = await readFile(this.path, 'utf8').then(JSON.parse).catch(error => {
      if (error.code === 'ENOENT') return null;
      throw new Error('Cannot read the channel cursor. Restore its state file before restarting.');
    });
    if (state !== null && (!Number.isSafeInteger(state.cursor) || state.cursor < 0)) throw new Error('Invalid channel cursor. Restore its state file before restarting.');
    this.cursor = state?.cursor ?? null;
  }

  async save(cursor) {
    await mkdir(dirname(this.path), { recursive: true, mode: 0o700 });
    const temporary = `${this.path}.${process.pid}.tmp`;
    await writeFile(temporary, JSON.stringify({ cursor }), { mode: 0o600 });
    await rename(temporary, this.path);
    this.cursor = cursor;
  }
}
