import { readFileSync } from 'node:fs';
import { readdir, stat } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { join } from 'node:path';
import { root } from './config.mjs';

export const version = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;
const execute = promisify(execFile);
const bridge = join(root, 'build/poki-native');

export async function buildInfo() {
  const [commit, native] = await Promise.all([
    execute('git', ['rev-parse', '--short', 'HEAD'], { cwd: root, timeout: 1000 }).then(result => result.stdout.trim(), () => 'unknown'),
    stat(bridge).catch(() => null),
  ]);
  return { commit, native_build: native?.mtime.toISOString() ?? 'unknown' };
}

export async function warnIfNativeStale() {
  const native = await stat(bridge).catch(() => null);
  if (!native) return;
  const directory = join(root, 'native/bridge');
  const files = await readdir(directory, { recursive: true }).catch(() => []);
  for (const file of files.filter(file => /(?:\.rs|Cargo\.toml|Cargo\.lock)$/.test(file) && !file.split('/').includes('target'))) {
    const source = await stat(join(directory, file)).catch(() => null);
    if (source?.mtimeMs > native.mtimeMs) {
      console.error('Warning: build/poki-native is older than its source; run ./bin/build-native when the device is available. Continuing with the existing bridge.');
      return;
    }
  }
}
