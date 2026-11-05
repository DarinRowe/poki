import { createHash, randomUUID } from 'node:crypto';
import { readFile, writeFile, mkdir, rename } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { z } from 'zod';

const entriesSchema = z.array(z.object({
  id: z.string().uuid(), text: z.string(), expiresAt: z.number().int().nonnegative(),
  receivedId: z.number().int().positive().nullable(),
}));
const retentionMilliseconds = 24 * 60 * 60 * 1000;

export class ReplyLedger {
  constructor(directory, scope) {
    this.path = join(directory, `bluebubbles-replies-${createHash('sha256').update(scope).digest('hex')}.json`);
    this.queue = Promise.resolve();
  }

  update(change) {
    this.queue = this.queue.then(async () => {
      if (!this.entries) {
        try { this.entries = entriesSchema.parse(JSON.parse(await readFile(this.path, 'utf8'))); }
        catch (error) {
          if (error.code !== 'ENOENT') throw new Error('Cannot read the reply ledger. Restore it before restarting.');
          this.entries = [];
        }
      }
      const before = JSON.stringify(this.entries);
      this.entries = this.entries.filter(entry => entry.receivedId !== null || entry.expiresAt > Date.now());
      const result = change();
      const after = JSON.stringify(this.entries);
      if (before !== after) {
        await mkdir(dirname(this.path), { recursive: true, mode: 0o700 });
        const temporary = `${this.path}.${process.pid}.tmp`;
        await writeFile(temporary, after, { mode: 0o600 });
        await rename(temporary, this.path);
      }
      return result;
    });
    return this.queue;
  }

  record(text) {
    return this.update(() => {
      const id = randomUUID();
      this.entries.push({ id, text, expiresAt: Date.now() + retentionMilliseconds, receivedId: null });
      return id;
    });
  }

  cancel(id) { return this.update(() => { this.entries = this.entries.filter(entry => entry.id !== id); }); }

  consume(messages) {
    return this.update(() => messages.map(message => {
      const entry = this.entries.find(entry => entry.receivedId === message.id) ??
        this.entries.find(entry => entry.receivedId === null && entry.text === message.text);
      if (!entry) return message;
      entry.receivedId = message.id;
      return { ...message, text: '' };
    }));
  }

  acknowledge(cursor) {
    return this.update(() => {
      this.entries = this.entries.filter(entry => entry.receivedId === null || entry.receivedId > cursor);
    });
  }
}
