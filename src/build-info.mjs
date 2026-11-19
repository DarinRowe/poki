import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { readdir, stat, readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { join } from 'node:path';
import { root } from './config.mjs';

export const version = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;
const execute = promisify(execFile);
const bridge = join(root, 'build/poki-native');

let fileDigests = new Map();

async function codeMarker() {
  const files = (await readdir(join(root, 'src'), { recursive: true }))
    .filter(file => /\.(?:mjs|json)$/.test(file)).map(file => join('src', file));
  files.push('package.json', 'build/poki-native');
  const previous = fileDigests;
  const entries = await Promise.all(files.sort().map(async file => {
    const path = join(root, file);
    try {
      // Metadata tells us when to read again. Only different bytes make the running build stale.
      const info = await stat(path, { bigint: true });
      const stamp = [info.dev, info.ino, info.size, info.mtimeNs, info.ctimeNs].join(':');
      const cached = previous.get(file);
      if (cached?.stamp === stamp) return [file, cached];
      const digest = createHash('sha256').update(await readFile(path)).digest('hex');
      return [file, { stamp, digest }];
    } catch (error) {
      if (error.code === 'ENOENT') return [file, { stamp: null, digest: null }];
      throw error;
    }
  }));
  fileDigests = new Map(entries);
  return JSON.stringify(entries.map(([file, { digest }]) => [file, digest]));
}

const startupCode = await codeMarker();

export async function requireCurrentCode() {
  if (await codeMarker() !== startupCode) {
    throw new Error('The service is running old code. Stop the running service and restart it with npm start.');
  }
}

export async function buildInfo() {
  // A container image has no git, so its build records the commit in build/commit (or POKI_BUILD_COMMIT).
  const recorded = async () => process.env.POKI_BUILD_COMMIT?.trim() || (await readFile(join(root, 'build/commit'), 'utf8').catch(() => '')).trim() || 'unknown';
  const [commit, native] = await Promise.all([
    execute('git', ['rev-parse', '--short', 'HEAD'], { cwd: root, timeout: 1000 }).then(result => result.stdout.trim() || recorded(), recorded),
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
