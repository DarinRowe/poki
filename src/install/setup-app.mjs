// Finds or installs Poki Setup for Mac: the newest PokiSetup-<version>-<build>-macos.dmg on the
// channel (same channel rule as desktop/core/src/release.rs), checked against SHA256SUMS-desktop.txt,
// Poki's Developer ID team and Apple's notarization before anything in it runs.
import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createReadStream, existsSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';

const exec = promisify(execFile);
export const REPO = 'JosssphZhou/poki';
export const TEAM_ID = 'Q64ZL36CJN';
const ORDER = ['stable', 'beta', 'alpha', 'pre-alpha'];
const BRIDGE = 'Contents/MacOS/poki-setup-bridge';

export class SetupError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function channelOf(tag, prerelease) {
  const rest = tag.replace(/^(ios|desktop)-/, '');
  if (rest === tag) return null;
  if (rest.startsWith('prealpha-')) return 'pre-alpha';
  if (rest.startsWith('alpha-')) return 'alpha';
  if (rest.startsWith('v')) return prerelease ? 'beta' : 'stable';
  return null;
}

async function github(path) {
  const response = await fetch(`https://api.github.com/repos/${REPO}${path}`, { headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'poki-install-iphone' } });
  if (!response.ok) throw new SetupError('setup_download_failed', `GitHub answered ${response.status} for ${path}`);
  return response.json();
}

// The newest macOS installer a channel offers, with the release that carries it.
export async function latestSetup(channel) {
  const allowed = ORDER.slice(0, ORDER.indexOf(channel) + 1);
  if (!allowed.length) throw new SetupError('unknown', `Unknown channel ${channel}; use ${ORDER.join(', ')}`);
  let best = null;
  for (const release of await github('/releases?per_page=40')) {
    if (release.draft || !allowed.includes(channelOf(release.tag_name, release.prerelease))) continue;
    for (const asset of release.assets) {
      const match = /^PokiSetup-(.+)-(\d+)-macos\.dmg$/.exec(asset.name);
      if (!match || (best && Number(match[2]) <= best.build)) continue;
      const sums = release.assets.find(a => a.name === 'SHA256SUMS-desktop.txt');
      best = { tag: release.tag_name, name: asset.name, version: match[1], build: Number(match[2]), url: asset.browser_download_url, sums: sums?.browser_download_url };
    }
  }
  if (!best) throw new SetupError('setup_download_failed', `No Poki Setup for macOS on the ${channel} channel`);
  if (!best.sums) throw new SetupError('setup_download_failed', `${best.tag} has no SHA256SUMS-desktop.txt`);
  return best;
}

async function download(url, file) {
  const response = await fetch(url, { headers: { 'User-Agent': 'poki-install-iphone' } });
  if (!response.ok) throw new SetupError('setup_download_failed', `${url} answered ${response.status}`);
  await writeFile(file, Buffer.from(await response.arrayBuffer()));
}

async function sha256(file) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}

// Developer ID team and notarization; throws setup_signature_invalid otherwise.
export async function verifyApp(app) {
  try {
    await exec('codesign', ['--verify', '--deep', '--strict', app]);
    const { stderr } = await exec('codesign', ['-dv', '--verbose=2', app]);
    if (!stderr.includes(`TeamIdentifier=${TEAM_ID}`)) throw new Error(`not signed by team ${TEAM_ID}`);
    const assessed = await exec('spctl', ['-a', '-t', 'exec', '-vv', app]).catch(error => error);
    const text = `${assessed.stdout ?? ''}${assessed.stderr ?? ''}`;
    if (!/accepted/.test(text) || !/Notarized Developer ID/.test(text)) throw new Error(`Gatekeeper: ${text.trim()}`);
  } catch (error) {
    throw new SetupError('setup_signature_invalid', `${app}: ${error.stderr?.trim() || error.message}`);
  }
}

async function buildOf(app) {
  const { stdout } = await exec('plutil', ['-extract', 'CFBundleVersion', 'raw', join(app, 'Contents/Info.plist')]).catch(() => ({ stdout: '0' }));
  return Number(stdout.trim()) || 0;
}

// Where an installed Poki Setup can be: the folder run installs into, then ~/Applications, then
// /Applications. run, phones and diagnose all look here, so they agree.
export function setupAppRoots(into) {
  return [...new Set([into, join(homedir(), 'Applications'), '/Applications'].filter(Boolean))];
}

// The helper inside the Poki Setup that run used (recorded in run.json) or, failing that, the first
// installed one. Throws setup_app_missing with every place it looked.
export function findSetupBridge({ recorded, into, roots = setupAppRoots(into) } = {}) {
  if (recorded && existsSync(recorded)) return recorded;
  for (const dir of roots) {
    const bridge = join(dir, 'Poki Setup.app', BRIDGE);
    if (existsSync(bridge)) return bridge;
  }
  throw new SetupError('setup_app_missing', `Poki Setup.app is not in ${roots.join(', ')}${recorded ? ` and the helper the last run used (${recorded}) is gone` : ''}. Run \`node bin/install-iphone.mjs run\` to install it, or pass --app-dir or --bridge.`);
}

// Returns { app, bridge, build, source }. An app already in /Applications or ~/Applications is used
// when it is at least as new as the channel's; otherwise the release is installed into `into`.
export async function ensureSetupApp({ channel, into = join(homedir(), 'Applications'), downloads, onNote = () => {} }) {
  const release = await latestSetup(channel);
  for (const app of ['/Applications/Poki Setup.app', join(homedir(), 'Applications/Poki Setup.app'), join(into, 'Poki Setup.app')]) {
    if (!existsSync(join(app, BRIDGE))) continue;
    const build = await buildOf(app);
    if (build < release.build) { onNote(`${app} is build ${build}; the ${channel} channel has ${release.build}`); continue; }
    await verifyApp(app);
    return { app, bridge: join(app, BRIDGE), build, version: release.version, source: 'installed' };
  }
  await mkdir(downloads, { recursive: true });
  const dmg = join(downloads, release.name);
  const sumsFile = join(downloads, `${release.tag}-SHA256SUMS-desktop.txt`);
  for (let attempt = 0; ; attempt++) {
    onNote(`Downloading ${release.name} from ${release.tag}`);
    await download(release.url, dmg);
    await download(release.sums, sumsFile);
    const want = (await readFile(sumsFile, 'utf8')).split('\n').map(line => line.trim().split(/\s+/)).find(([, name]) => name === release.name)?.[0];
    if (!want) throw new SetupError('setup_checksum_mismatch', `${release.name} is not listed in SHA256SUMS-desktop.txt`);
    if ((await sha256(dmg)) === want) break;
    await rm(dmg, { force: true });
    if (attempt >= 1) throw new SetupError('setup_checksum_mismatch', `${release.name} does not match SHA256SUMS-desktop.txt twice in a row`);
  }
  onNote('Checksum matches SHA256SUMS-desktop.txt');
  const mount = await mkdtemp(join(downloads, 'mount-'));
  await exec('hdiutil', ['attach', '-nobrowse', '-readonly', '-noautoopen', '-mountpoint', mount, dmg]);
  try {
    const source = join(mount, 'Poki Setup.app');
    await verifyApp(source);
    onNote(`Signed by Developer ID team ${TEAM_ID} and notarized`);
    await mkdir(into, { recursive: true });
    const app = join(into, 'Poki Setup.app');
    await rm(app, { recursive: true, force: true });
    await exec('ditto', [source, app]);
    return { app, bridge: join(app, BRIDGE), build: release.build, version: release.version, source: release.tag };
  } finally {
    await exec('hdiutil', ['detach', mount, '-quiet']).catch(() => exec('hdiutil', ['detach', mount, '-force', '-quiet']).catch(() => {}));
    await rm(mount, { recursive: true, force: true }).catch(() => {});
  }
}
