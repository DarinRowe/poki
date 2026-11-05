#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { createInterface } from 'node:readline';
import { mkdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { PhoneTask } from './task-runner.mjs';
import { safeModelError } from './model-config.mjs';

async function main() {
  const { values, positionals } = parseArgs({ allowPositionals: true, options: {
    device: { type: 'string' }, state: { type: 'string' }, model: { type: 'string' },
    auth: { type: 'string' }, 'service-tier': { type: 'string' },
    context: { type: 'string' }, 'step-timeout': { type: 'string' },
    help: { type: 'boolean', short: 'h' },
  } });
  if (values.help) {
    console.log('Usage: node agent/cli.mjs --device <device UUID> [--state <directory>] [--context "task context"] [--step-timeout <seconds>] "task"\nStep timeout defaults to 60 seconds; there is no whole-task timeout. Use /stop to stop.');
  } else if (!values.device || !positionals.join(' ').trim()) {
    console.error('A device and a task are required. Use --help.'); process.exitCode = 2;
  } else {
    const stateDirectory = resolve(values.state ?? 'agent/.runtime');
    const task = new PhoneTask(positionals.join(' '), values.device, { stateDirectory, stepTimeout: values['step-timeout'], context: values.context, model: values.model, auth: values.auth, ...(values['service-tier'] === undefined ? {} : { serviceTier: values['service-tier'] }) });
    const input = createInterface({ input: process.stdin });
    input.on('line', line => {
      try {
        if (line === '/stop') void task.stop();
        else task.steer(line);
      } catch (error) { console.error(error.message); }
    });
    let previous;
    task.on('snapshot', snapshot => {
      const status = { phase: snapshot.phase, title: snapshot.title, result: snapshot.result };
      const next = JSON.stringify(status);
      if (previous !== next) { console.log(next); previous = next; }
    });
    task.on('warning', message => console.error(message));
    process.once('SIGINT', () => void task.stop());
    await new Promise((resolveDone, reject) => {
      task.once('closed', () => {
        void (async () => {
          input.close();
          await mkdir(join(stateDirectory, 'tasks'), { recursive: true, mode: 0o700 });
          await writeFile(join(stateDirectory, 'tasks', `${task.snapshot.id}.json`), JSON.stringify(task.snapshot, null, 2), { mode: 0o600 });
          console.log(JSON.stringify({ type: 'result', ...task.snapshot }));
          process.exitCode = task.snapshot.phase === 'completed' ? 0 : 1;
          resolveDone();
        })().catch(reject);
      });
      void task.start();
    });
  }

}
main().catch(error => { console.error(safeModelError(error)); process.exitCode = 1; });
