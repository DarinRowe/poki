import http from 'node:http';
import { EventEmitter, once } from 'node:events';
import { appendFile } from 'node:fs/promises';

export async function makeMessages({ selfChat = false } = {}) {
  const fixture = new EventEmitter();
  Object.assign(fixture, { selfChat, rows: [], sent: [], requests: [], password: 'local-bluebubbles-test-secret' });
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const send = (status, data) => res.writeHead(status, { 'content-type': 'application/json' }).end(JSON.stringify({ status, data }));
    if (url.searchParams.get('password') !== fixture.password) { send(401, null); return; }
    let raw = ''; for await (const chunk of req) raw += chunk;
    const body = raw ? JSON.parse(raw) : null;
    fixture.requests.push({ method: req.method, path: url.pathname, body });
    if (url.pathname === '/api/v1/ping' && req.method === 'GET') { send(200, null); return; }
    if (url.pathname === '/api/v1/message/query' && req.method === 'POST') {
      const filters = new Map(body.where?.map(item => [item.statement, item.args]));
      const chat = filters.get('chat.guid = :chatGuid')?.chatGuid;
      const sender = filters.get('handle.id = :sender')?.sender;
      const cursor = filters.get('message.ROWID > :cursor')?.cursor;
      const nullableReaction = filters.has('(message.associatedMessageType = :reaction OR message.associatedMessageType IS NULL)');
      const reaction = filters.get('message.associatedMessageType = :reaction') ?? filters.get('(message.associatedMessageType = :reaction OR message.associatedMessageType IS NULL)');
      if (!chat || !sender || !Number.isSafeInteger(cursor) ||
          filters.get('message.isFromMe = :outgoing')?.outgoing !== false ||
          reaction?.reaction !== 0) { send(400, null); return; }
      const rows = fixture.rows.filter(row => row.originalROWID > cursor && row.handle.address === sender &&
        row.chats.some(item => item.guid === chat) && !row.isFromMe && (row.associatedMessageType === 0 || nullableReaction && row.associatedMessageType === null));
      rows.sort((a, b) => a.dateCreated - b.dateCreated);
      send(200, fixture.leak ? [fixture.leak] : rows.slice(body.offset, body.offset + body.limit));
      fixture.emit('read');
      return;
    }
    if (url.pathname === '/api/v1/message/text' && req.method === 'POST') {
      if (fixture.sendError) { send(fixture.sendError, null); return; }
      const message = { ...body, guid: `reply-${fixture.sent.length + 1}` };
      fixture.sent.push(message);
      if (fixture.selfChat) {
        addMessage(fixture, body.message, { outgoing: 1, reaction: null });
        addMessage(fixture, body.message, { reaction: null });
      }
      if (fixture.outbox) await appendFile(fixture.outbox, JSON.stringify({ text: body.message }) + '\n');
      send(200, message);
      fixture.emit('reply', body.message);
      return;
    }
    send(404, null);
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  fixture.url = `http://127.0.0.1:${server.address().port}`;
  fixture.close = async () => { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); };
  return fixture;
}

export function addMessage(fixture, text, { sender = 1, chat = sender, outgoing = 0, reaction = 0, dateCreated = Date.now() } = {}) {
  const address = sender === 1 ? 'allowed@example.test' : 'other@example.test';
  const id = fixture.rows.length + 1;
  fixture.rows.push({ originalROWID: id, guid: `message-${id}`, text, dateCreated,
    handle: { address }, chats: [{ guid: chat === 3 ? 'iMessage;+;group' : `${fixture.selfChat ? 'any' : 'iMessage'};-;${address}` }],
    isFromMe: Boolean(outgoing), associatedMessageType: reaction });
  return id;
}
