#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { existsSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { root } from '../src/config.mjs';

const args = process.argv.slice(2);
if (args.length) {
  console.log('Usage: poki update\nUpdate a clean main checkout, or show prebuilt package download instructions.');
  process.exit(args.length === 1 && ['--help', '-h'].includes(args[0]) ? 0 : 1);
}

function git(...args) {
  const result = spawnSync('git', args, { cwd: root, encoding: 'utf8' });
  if (result.error || result.status !== 0) throw new Error('Git could not inspect this checkout. Check that Git is installed and the repository is readable.');
  return result.stdout.trim();
}

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit' });
  if (result.error || result.status !== 0) throw new Error(`${command} failed. Resolve the error above and run poki update again. The service was not restarted.`);
}

try {
  if (!existsSync(join(root, '.git'))) {
    console.log('Prebuilt Poki package. Download the latest macOS arm64 archive:\nhttps://github.com/JosssphZhou/poki/releases/latest\nExtract it into a new directory, then run npm ci --no-audit --no-fund there.\nIf you use Poki Agent, also run npm ci --prefix agent.\nStop your existing service, start npm start from the new directory, and update your MCP client path and shell PATH to that directory.\nKeep your existing POKI_MCP_STATE_DIR. The current installation was not changed.');
  } else {
    if (realpathSync(git('rev-parse', '--show-toplevel')) !== realpathSync(root)) throw new Error('Poki must be at the root of its own Git checkout.');
    if (git('branch', '--show-current') !== 'main') throw new Error('Update stopped: this checkout is not on main. Switch to main yourself before updating.');
    if (git('status', '--porcelain', '--untracked-files=all')) throw new Error('Update stopped: this checkout has local changes. Commit or stash them yourself before updating.');
    console.log('Fetching Poki updates...');
    run('git', ['fetch']);
    console.log('Fast-forwarding Poki without overwriting ignored files...');
    run('git', ['merge', '--ff-only', '--no-overwrite-ignore', '@{upstream}']);
    console.log('Building Poki with ./bin/setup...');
    run('./bin/setup', []);
    console.log('Poki updated. Stop the existing service and restart it with npm start. The service was not restarted automatically.');
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
