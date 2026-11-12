import { spawn } from 'node:child_process';
import { join } from 'node:path';
import { root } from './config.mjs';
import { phase, work } from './work.mjs';

const maxMessageBytes = 8 * 1024 * 1024;
const limits = {
  warmup: 180000, warmupIdle: 90000, idle: 900000, cooldown: 600000,
  reply: 120, admission: 100, hardReply: 5000, slowCooldown: 10000, kill: 1000,
};

function similar(a, b) {
  if (a.key !== b.key || a.pixels.length !== b.pixels.length) return false;
  let difference = 0;
  for (let i = 0; i < a.pixels.length; i++) difference += Math.abs(a.pixels[i] - b.pixels[i]);
  return difference <= a.pixels.length * 8;
}

function validRows(rows) {
  return Array.isArray(rows) && rows.every(row => row && typeof row.text === 'string' &&
    [row.x, row.y, row.width, row.height, row.confidence].every(Number.isFinite) &&
    row.width > 0 && row.height > 0 && row.confidence >= 0 && row.confidence <= 1);
}

// The daemon owns one worker. A timed-out or cancelled caller leaves its slot
// occupied until Vision finishes or the hard deadline reaps the process.
export class VisionOCR {
  constructor({
    start = () => spawn(join(root, 'build/ocr'), ['--worker'], { stdio: ['pipe', 'pipe', 'ignore'] }),
    timeouts = {},
  } = {}) {
    this.start = start;
    this.limits = { ...limits, ...timeouts };
    this.retryAfter = 0;
    this.nextId = 0;
  }

  warm() {
    let worker = this.worker;
    if (!worker && !this.closed && performance.now() >= this.retryAfter) {
      let child;
      try { child = this.start(); }
      catch { this.retryAfter = performance.now() + this.limits.cooldown; return; }
      worker = { child, buffer: '', failures: 0, pages: [], sampled: false };
      this.worker = worker;
      worker.closed = new Promise(resolve => child.once('close', () => {
        clearTimeout(worker.idle);
        clearTimeout(worker.kill);
        this.finish(worker, undefined);
        if (!worker.retiring) this.retryAfter = performance.now() + this.limits.cooldown;
        if (this.worker === worker) this.worker = undefined;
        resolve();
      }));
      child.on('error', () => this.retire(worker, this.limits.cooldown));
      child.stdin.on('error', () => this.retire(worker, this.limits.cooldown));
      child.stdout.setEncoding('utf8');
      child.stdout.on('data', chunk => this.receive(worker, chunk));
    }
    return worker;
  }

  scheduleIdle(worker, ms) {
    clearTimeout(worker.idle);
    worker.idle = setTimeout(() => this.retire(worker), ms);
    worker.idle.unref();
  }

  retire(worker, cooldown = 0) {
    if (worker.retiring) return worker.closed;
    worker.retiring = true;
    this.retryAfter = Math.max(this.retryAfter, performance.now() + cooldown);
    clearTimeout(worker.idle);
    this.finish(worker, undefined);
    worker.child.kill('SIGTERM');
    worker.kill = setTimeout(() => worker.child.kill('SIGKILL'), this.limits.kill);
    worker.kill.unref();
    return worker.closed;
  }

  receive(worker, chunk) {
    if (worker.retiring) return;
    worker.buffer += chunk;
    if (Buffer.byteLength(worker.buffer) > maxMessageBytes) {
      this.retire(worker, this.limits.cooldown);
      return;
    }
    const lines = worker.buffer.split('\n');
    worker.buffer = lines.pop();
    for (const line of lines) {
      if (worker.retiring) return;
      let message;
      try { message = JSON.parse(line); }
      catch { this.retire(worker, this.limits.cooldown); return; }
      if (message?.pressure === 'critical' || message?.pressure === 'warning') {
        if (message.pressure === 'critical' || !worker.pending) this.retire(worker, this.limits.warmupIdle);
        else worker.pressureWarning = true;
      } else if (worker.pending && message?.id === worker.pending.id) {
        const job = worker.pending;
        const valid = validRows(message.rows);
        if (job.probe) {
          worker.sampled = true;
          const fast = valid && message.rows.length > 0 && performance.now() - job.started <= this.limits.admission;
          job.page.fast = fast ? job.page.fast + 1 : 0;
          job.page.slow = fast ? 0 : job.page.slow + 1;
          if (job.page.slow >= 2) {
            job.page.nextProbe = performance.now() + this.limits.slowCooldown;
            job.page.slow = 0;
          }
        } else if (!job.cancelled) {
          worker.failures = valid ? 0 : worker.failures + 1;
          if (!valid) this.demote(job.page);
        }
        this.finish(worker, valid ? message.rows : undefined);
        if (worker.pressureWarning) this.retire(worker, this.limits.warmupIdle);
        else if (worker.failures >= 2) this.retire(worker, this.limits.cooldown);
        else this.scheduleIdle(worker, this.limits.idle);
      }
    }
  }

  finish(worker, rows) {
    const job = worker.pending;
    if (!job) return;
    worker.pending = undefined;
    clearTimeout(job.hard);
    job.respond(rows);
  }

  page(worker, descriptor) {
    const index = worker.pages.findIndex(page => similar(page.descriptor, descriptor));
    const page = index < 0
      ? { descriptor, fast: 0, slow: 0, nextProbe: 0 }
      : worker.pages.splice(index, 1)[0];
    worker.pages.push(page);
    if (worker.pages.length > 16) worker.pages.shift();
    return page;
  }

  demote(page) {
    page.fast = 0;
    page.nextProbe = performance.now() + this.limits.slowCooldown;
  }

  submit(worker, image, page, { probe, respond }) {
    clearTimeout(worker.idle);
    const id = ++this.nextId;
    const hard = setTimeout(() => this.retire(worker, this.limits.cooldown),
      probe ? this.limits.warmup : this.limits.hardReply);
    hard.unref();
    const job = { id, hard, respond, page, probe, started: performance.now() };
    worker.pending = job;
    if (probe && !worker.sampled) this.scheduleIdle(worker, this.limits.warmupIdle);
    worker.child.stdin.write(JSON.stringify({ id, image: image.toString('base64') }) + '\n');
    return job;
  }

  recognize(image, { descriptor, signal, budget = Infinity } = {}) {
    signal?.throwIfAborted();
    if (image.byteLength > maxMessageBytes / 2 || budget <= this.limits.reply) return;
    const worker = work.exit(() => this.warm());
    if (!worker || worker.retiring) return;
    if (worker.pending) {
      if (!worker.sampled) work.exit(() => this.scheduleIdle(worker, this.limits.warmupIdle));
      return;
    }

    const page = this.page(worker, descriptor);
    if (page.fast < 2) {
      if (performance.now() >= page.nextProbe) {
        work.exit(() => this.submit(worker, image, page, { probe: true, respond() {} }));
      }
      return;
    }

    return phase('ocr_vision_attempt', () => new Promise((resolve, reject) => {
      const cleanup = () => { clearTimeout(soft); signal?.removeEventListener('abort', abort); };
      const abort = () => { job.cancelled = true; cleanup(); reject(signal.reason); };
      const soft = setTimeout(() => { this.demote(page); cleanup(); resolve(undefined); }, this.limits.reply);
      const job = this.submit(worker, image, page, { probe: false, respond: rows => { cleanup(); resolve(rows); } });
      signal?.addEventListener('abort', abort, { once: true });
    }));
  }

  close() {
    this.closed = true;
    if (this.worker) return this.retire(this.worker);
  }
}
