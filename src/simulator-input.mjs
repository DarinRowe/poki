import { execFile, spawn } from 'node:child_process';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { checkWork, phase, signal } from './work.mjs';
import { root } from './config.mjs';

const idleMs = 30000, nothingSent = 75;
const sessions = new Map();

// A simulator created on a Chinese Mac types through Pinyin, which turns "hello poki" into "hellopo ki"
// and "!" into "！", and its pasteboard is no way around that on iOS 27: simctl pbcopy and the pasteboard
// interface both leave it empty. Selecting en_US right after a freshly launched app's first focus can be
// lost, so this runs before launches and new connections, and again before typing in case something else
// changed the keyboard since. Typing checks its own result, so a failure here only fails that check.
export const selectKeyboard = id => new Promise(resolve => execFile('xcrun', ['simctl', 'keyboard', id, 'en_US'], { timeout: 10000 }, () => resolve()));

// One helper per simulator holds the input connection while input keeps coming, because a connection
// that closes straight after a tap can lose the tap. native/simulator.md explains why.
class InputSession {
  ready = false;
  stderr = '';

  constructor(id) {
    this.id = id;
    this.tail = selectKeyboard(id).then(() => this.start());
  }

  start() {
    this.child = spawn(join(root, 'build/simulator'), ['--hid-session', this.id], { detached: true, stdio: 'pipe' });
    this.child.stdin.on('error', () => {});
    this.child.stderr.on('data', chunk => { this.stderr = (this.stderr + chunk).slice(-4000); });
    createInterface({ input: this.child.stdout }).on('line', line => {
      const reply = JSON.parse(line);
      if (reply.ready) this.ready = true;
      else this.request?.done(reply);
    });
    this.child.once('error', error => { this.stderr ||= error.message; });
    this.child.once('close', code => this.closed(code));
    // The helper ends when its input closes, so it must not keep the service alive on exit.
    this.child.unref();
    for (const stream of [this.child.stdin, this.child.stdout, this.child.stderr]) stream.unref?.();
  }

  forget() { if (sessions.get(this.id) === this) sessions.delete(this.id); }

  closed(code) {
    this.forget();
    this.exit = code ?? 'signal';
    clearTimeout(this.idle); clearTimeout(this.escalation);
    this.request?.failed(code);
  }

  closeWhenIdle() {
    this.idle = setTimeout(() => { this.forget(); this.child.stdin.end(); }, idleMs);
    this.idle.unref();
  }

  // Interrupting the helper makes it release any held touch or key before it exits.
  interrupt() {
    this.forget();
    const send = name => { try { process.kill(-this.child.pid, name); } catch (error) { if (error.code !== 'ESRCH') this.child.kill(name); } };
    send('SIGTERM');
    this.escalation = setTimeout(() => send('SIGKILL'), 1000);
  }

  failure(code) {
    const reason = this.stderr.trim().replace(/\.$/, '');
    const error = new Error(this.ready
      ? `Command did not complete: ${reason}. An input may already have been delivered; inspect before retrying.`
      : `Simulator input did not start: ${reason || 'the helper did not answer. If build/simulator is older than this version, run npm run build:native'}.`);
    error.nothingSent = code === nothingSent;
    return error;
  }

  send(events, timeout) {
    const run = () => new Promise((resolve, reject) => {
      if (this.exit !== undefined) { reject(this.failure(nothingSent)); return; }
      const caller = signal();
      const limit = new AbortController();
      const timer = setTimeout(() => limit.abort(new DOMException('External process deadline exceeded', 'TimeoutError')), timeout);
      const request = caller ? AbortSignal.any([caller, limit.signal]) : limit.signal;
      const interrupt = () => this.interrupt();
      request.addEventListener('abort', interrupt, { once: true });
      const finish = () => { clearTimeout(timer); request.removeEventListener('abort', interrupt); this.request = undefined; };
      this.request = {
        done: reply => { finish(); this.closeWhenIdle(); resolve(reply); },
        // A helper that never got ready says more than the deadline it ran into.
        failed: code => { finish(); reject(request.aborted && (this.ready || caller?.aborted) ? request.reason : this.failure(code)); },
      };
      clearTimeout(this.idle);
      this.child.stdin.write(`${JSON.stringify({ events })}\n`);
    });
    const result = this.tail.then(run);
    this.tail = result.catch(() => {});
    return result;
  }
}

function sessionFor(id) {
  let session = sessions.get(id);
  if (!session) { session = new InputSession(id); sessions.set(id, session); session.closeWhenIdle(); }
  return session;
}

// Opening ahead of a launch spends the connection's setup time while the app is starting anyway.
export function openInput(id) { sessionFor(id); }

export function sendInput(id, events, timeout) {
  checkWork();
  return phase('external_process', async () => {
    try { return await sessionFor(id).send(events, timeout); }
    catch (error) {
      // The simulator restarted while the connection sat idle, and nothing from this request went out.
      if (!error.nothingSent) throw error;
      return sessionFor(id).send(events, timeout);
    }
  });
}
