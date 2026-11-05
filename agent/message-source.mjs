import { randomUUID } from 'node:crypto';
import { ChannelCursor, channelURL } from './channel-state.mjs';
import { ReplyLedger } from './reply-ledger.mjs';

export class MessageSource {
  constructor({ sender, chatGuid, stateDirectory }) {
    if (typeof sender !== 'string' || !sender.trim() || sender.includes(';')) throw new Error('Configure exactly one iMessage sender.');
    this.sender = sender.trim();
    this.chatGuid = chatGuid ?? `iMessage;-;${this.sender}`;
    if (![`iMessage;-;${this.sender}`, `any;-;${this.sender}`].includes(this.chatGuid)) {
      throw new Error('Configure the exact direct chat GUID for the configured sender.');
    }
    this.url = channelURL(process.env.BLUEBUBBLES_URL, 'BLUEBUBBLES_URL');
    this.password = process.env.BLUEBUBBLES_PASSWORD;
    if (!this.password) throw new Error('Set BLUEBUBBLES_PASSWORD in the environment.');
    this.progressStyle = 'opening';
    this.ledger = new ReplyLedger(stateDirectory, `${this.url.origin}/${this.chatGuid}`);
    this.state = new ChannelCursor(stateDirectory, 'bluebubbles', `${this.url.origin}/${this.sender}`);
  }

  async request(path, body, signal) {
    const url = new URL(`/api/v1/${path}`, this.url);
    url.searchParams.set('password', this.password);
    let response;
    try {
      response = await fetch(url, { method: body ? 'POST' : 'GET', redirect: 'error',
        headers: { 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined,
        signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(20000)]) : AbortSignal.timeout(20000) });
    } catch {
      if (signal?.aborted) throw signal.reason;
      throw new Error('BlueBubbles request failed. Delivery may be uncertain; no automatic resend was attempted.');
    }
    if (!response.ok) throw Object.assign(new Error(`BlueBubbles request rejected (HTTP ${response.status}). Check the server and credentials.`), { status: response.status });
    const result = await response.json().catch(() => { throw new Error('BlueBubbles returned invalid JSON.'); });
    if (result.status !== 200) throw Object.assign(new Error('BlueBubbles did not confirm the request.'), { status: result.status });
    return result.data;
  }

  async check(signal) {
    await this.request('ping', undefined, signal);
    await this.query(0, signal);
  }

  async open(signal) {
    await this.request('ping', undefined, signal);
    await this.state.open();
    if (this.state.cursor === null) {
      const messages = await this.query(0, signal);
      await this.acknowledge(messages.reduce((id, message) => Math.max(id, message.id), 0));
    }
  }

  async query(cursor, signal) {
    const messages = [];
    for (let offset = 0; ; offset += 1000) {
      const rows = await this.request('message/query', {
        with: ['chats', 'attributedBody'], sort: 'ASC', limit: 1000, offset,
        where: [
          { statement: 'chat.guid = :chatGuid', args: { chatGuid: this.chatGuid } },
          { statement: 'message.ROWID > :cursor', args: { cursor } },
          { statement: 'handle.id = :sender', args: { sender: this.sender } },
          { statement: 'message.isFromMe = :outgoing', args: { outgoing: false } },
          { statement: '(message.associatedMessageType = :reaction OR message.associatedMessageType IS NULL)', args: { reaction: 0 } },
        ],
      }, signal);
      if (!Array.isArray(rows)) throw new Error('BlueBubbles returned an invalid message list.');
      for (const row of rows) {
        if (!Number.isSafeInteger(row.originalROWID) || row.originalROWID <= 0) throw new Error('BlueBubbles returned an invalid message ID.');
        if (row.originalROWID <= cursor) continue;
        if (row.handle?.address !== this.sender || row.isFromMe !== false ||
            (row.associatedMessageType ?? 0) !== 0 || !row.chats?.some(chat => chat.guid === this.chatGuid)) {
          throw new Error('BlueBubbles returned a message outside the configured sender scope.');
        }
        const text = typeof row.text === 'string' ? row.text : null;
        const isReply = text !== null && text.trimStart().startsWith('🤖 Codex：');
        messages.push({ id: row.originalROWID, text: isReply ? '' : text });
      }
      if (rows.length < 1000) break;
    }
    return [...new Map(messages.map(message => [message.id, message])).values()].sort((a, b) => a.id - b.id);
  }

  async read(signal) { return this.ledger.consume(await this.query(this.state.cursor, signal)); }
  async acknowledge(id) {
    await this.state.save(id);
    await this.ledger.acknowledge(id);
  }
  replyTo() { return this; }

  async send(text) {
    const id = await this.ledger.record(text);
    try {
      await this.request('message/text', { chatGuid: this.chatGuid, message: text, tempGuid: randomUUID(), method: 'apple-script' });
    } catch (error) {
      if (error.status >= 400 && error.status < 500 && error.status !== 408) await this.ledger.cancel(id);
      throw error;
    }
  }
}
