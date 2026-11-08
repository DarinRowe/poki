#!/usr/bin/env node
// Installs Poki on an iPhone through Poki Setup without its window. Read INSTALL-IPHONE.md first.
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { Bridge } from '../src/install/bridge.mjs';
import { findSetupBridge, SetupError } from '../src/install/setup-app.mjs';
import { installerLabel, installerVersion } from '../src/install/version.mjs';
import { diagnose, issueDraft, readRun } from '../src/install/report.mjs';
import { codeCommand, defaultStateDir, manifest, run } from '../src/install/run.mjs';

const usage = `Usage: node bin/install-iphone.mjs <command> [options]

Commands:
  run                 Install Poki on the iPhone, stopping only where a person has to act.
  code                Hand the running install the Apple two-factor code. The person runs this in their own
                      Terminal and types the code at the hidden prompt (or pipes it in). Never as an argument.
  done <step>         Tell the running install that the person finished a step it cannot see (open_poki).
  phones              List the iPhones Poki Setup can reach (to choose one with --udid).
  diagnose            Print a diagnostics bundle with identifiers and secrets removed.
  issue               Draft an English issue from the last run. It prints the draft and the gh command;
                      it never submits. Show the draft to the person first.
  steps               Print the steps, who does each one, and the error codes.

Options:
  --channel <name>    stable, beta, alpha (default) or pre-alpha.
  --udid <udid>       The iPhone to use when several are plugged in.
  --dry-run           Download and check the real Poki Setup, start its real helper, then simulate the
                      iPhone and the Apple Account. Nothing touches a device or Apple.
  --json              One JSON event per line (for agents).
  --state <dir>       Where the run keeps its record (default ~/Library/Application Support/PokiInstall).
  --setup-home <dir>  Poki Setup's data directory (default: Poki Setup's own, shared with the app).
  --bridge <path>     Use this poki-setup-bridge instead of the one in Poki Setup.app.
  --app-dir <dir>     Where to put Poki Setup.app when it is not installed (default ~/Applications).
  --reinstall         Sign and install again even when the last run installed Poki.
  --version           Print the installer's version and build commit.
  --no-device         diagnose only: do not ask usbmuxd, devicectl or Bonjour about devices.

Exit codes: 0 done, 1 bad usage, 2 a step failed (see the code), 3 a person step is still open (run again).`;

const { values: opts, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    channel: { type: 'string', default: 'alpha' },
    udid: { type: 'string' },
    'dry-run': { type: 'boolean', default: false },
    json: { type: 'boolean', default: false },
    state: { type: 'string' },
    'setup-home': { type: 'string' },
    bridge: { type: 'string' },
    'app-dir': { type: 'string' },
    reinstall: { type: 'boolean', default: false },
    'no-device': { type: 'boolean', default: false },
    version: { type: 'boolean', short: 'v', default: false },
    help: { type: 'boolean', short: 'h', default: false },
  },
});
if (opts.version) {
  console.log(`Poki installer ${installerLabel(await installerVersion())}`);
  process.exit(0);
}
const [command, arg] = positionals;
const dryRun = opts['dry-run'];
const state = resolve(opts.state ?? join(defaultStateDir(), dryRun ? 'dry-run' : ''));
const appDir = opts['app-dir'] ? resolve(opts['app-dir']) : dryRun ? join(state, 'app') : undefined;
const setupHome = opts['setup-home'] ? resolve(opts['setup-home']) : dryRun ? join(state, 'setup-home') : undefined;
await mkdir(join(state, 'inbox'), { recursive: true });

// The Apple code is single-use but still a credential: it is read from a hidden prompt or stdin,
// never from argv, where ps and shell history would show it.
async function readSecret(prompt) {
  if (!process.stdin.isTTY) {
    let text = '';
    for await (const chunk of process.stdin) text += chunk;
    return text.trim();
  }
  process.stderr.write(prompt);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  let text = '';
  for await (const chunk of process.stdin) {
    const input = chunk.toString();
    if (input.includes('\u0003')) { process.stderr.write('\n'); process.exit(130); }
    const end = input.search(/[\r\n]/);
    text += end < 0 ? input : input.slice(0, end);
    if (end >= 0) break;
  }
  process.stdin.setRawMode(false);
  process.stderr.write('\n');
  return text.trim();
}

async function inbox(name, value) {
  const file = join(state, 'inbox', name);
  await writeFile(file, value, { mode: 0o600 });
}

// phones and diagnose start the helper the last run used, else the Poki Setup run would use.
async function bridgePath() {
  if (opts.bridge) {
    if (!existsSync(resolve(opts.bridge))) throw new SetupError('setup_app_missing', `${resolve(opts.bridge)} does not exist`);
    return resolve(opts.bridge);
  }
  return findSetupBridge({ recorded: (await readRun(state))?.setup_bridge, into: appDir });
}

switch (opts.help ? 'help' : command) {
  case 'run':
    process.exitCode = await run({ state, setupHome, channel: opts.channel, udid: opts.udid, dryRun, json: opts.json, bridge: opts.bridge && resolve(opts.bridge), appDir, reinstall: opts.reinstall });
    break;
  case 'code':
    if (arg !== undefined) { console.error(`Do not put the Apple code on the command line. Run: ${codeCommand(state)} (and type it at the hidden prompt).`); process.exitCode = 1; break; }
    {
      const digits = await readSecret('Apple code (6 digits, not shown): ');
      if (!/^\d{6}$/.test(digits)) { console.error('The Apple code has 6 digits.'); process.exitCode = 1; break; }
      await inbox('apple-code', digits);
    }
    console.log('Handed the code to the running install.');
    break;
  case 'done':
    if (arg !== 'open_poki') { console.error('Only open_poki is confirmed by hand: node bin/install-iphone.mjs done open_poki'); process.exitCode = 1; break; }
    await inbox(arg, 'done');
    console.log(`Told the running install that ${arg} is done.`);
    break;
  case 'phones': {
    try {
      const path = await bridgePath();
      const { bridge } = await Bridge.start(path, { env: setupHome ? { POKI_SETUP_HOME: setupHome } : {} });
      try {
        for (const r of await bridge.request('phones')) console.log(`${r.phone.udid}  ${r.facts?.product_type ?? '?'}  iOS ${r.facts?.ios ?? '?'}  ${r.phone.link?.kind ?? ''}`);
      } finally { bridge.close(); }
    } catch (error) {
      console.error(`${error.code ?? error.kind ?? 'error'}: ${error.message}`);
      process.exitCode = 2;
    }
    break;
  }
  case 'diagnose':
    process.stdout.write((await diagnose({ state, noDevice: opts['no-device'], bridge: opts.bridge && resolve(opts.bridge), appDir, setupHome })).text);
    break;
  case 'issue': {
    const draft = await issueDraft({ state });
    console.log(`Title: ${draft.title}\n\n${draft.body}`);
    console.log(`Saved to ${draft.draftFile}.\n\nShow this draft to the person and submit it only after they say yes. Then run:\n  ${draft.command}`);
    break;
  }
  case 'steps':
    console.log(JSON.stringify(manifest, null, 2));
    break;
  default:
    console.log(usage);
    process.exitCode = command && !opts.help ? 1 : 0;
}
