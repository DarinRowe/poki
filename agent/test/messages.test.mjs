import test from 'node:test';
import assert from 'node:assert/strict';
import { makeMessages, addMessage } from './fixtures/messages.mjs';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { MessageSource } from '../message-source.mjs';

test('BlueBubbles limits reads and replies to one sender, skips history and resumes consumed IDs', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'poki-message-test-'));
  const fixture = await makeMessages({ selfChat: true });
  const before = { ...process.env };
  process.env.BLUEBUBBLES_URL = fixture.url;
  process.env.BLUEBUBBLES_PASSWORD = fixture.password;
  t.after(async () => {
    for (const key of ['BLUEBUBBLES_URL', 'BLUEBUBBLES_PASSWORD']) {
      if (before[key] === undefined) delete process.env[key]; else process.env[key] = before[key];
    }
    await fixture.close(); await rm(directory, { recursive: true, force: true });
  });
  addMessage(fixture, 'History must not execute');
  const options = { sender: 'allowed@example.test', chatGuid: 'any;-;allowed@example.test', stateDirectory: directory };
  let source = new MessageSource(options);
  await source.open();
  assert.deepEqual(await source.read(), []);
  const expectedId = addMessage(fixture, 'Allowed task');
  const plainId = addMessage(fixture, 'Plain message without reaction metadata', { reaction: null });
  addMessage(fixture, 'Private other task', { sender: 2 });
  addMessage(fixture, 'Group content', { chat: 3 });
  addMessage(fixture, 'Allowed task', { outgoing: 1, reaction: null });
  addMessage(fixture, 'Reaction', { reaction: 2000 });
  assert.deepEqual(await source.read(), [{ id: expectedId, text: 'Allowed task' }, { id: plainId, text: 'Plain message without reaction metadata' }]);
  await source.acknowledge(plainId);
  await source.send('Task received');
  assert.equal(fixture.sent[0].message, 'Task received', 'Replies must preserve the exact plain text');
  source = new MessageSource(options);
  await source.open();
  const legacyId = addMessage(fixture, '🤖 Codex：\nLegacy reply', { reaction: null });
  const ignored = await source.read();
  assert.deepEqual(ignored, [
    { id: legacyId - 1, text: '' },
    { id: legacyId, text: '' },
  ], 'Synchronized bot replies must be acknowledged without dispatch');
  source = new MessageSource(options);
  await source.open();
  assert.deepEqual(await source.read(), ignored, 'A crash before cursor acknowledgement must not replay a reply as a task');
  await source.acknowledge(legacyId);
  const sameTextId = addMessage(fixture, 'Task received', { reaction: null });
  assert.deepEqual(await source.read(), [{ id: sameTextId, text: 'Task received' }]);
  await source.acknowledge(sameTextId);
  source = new MessageSource(options);
  await source.open();
  assert.deepEqual(await source.read(), []);
  const ids = Array.from({ length: 1001 }, (_, i) => addMessage(fixture, `Task ${i}`, { dateCreated: 1001 - i }));
  const messages = await source.read();
  assert.deepEqual(messages.map(message => message.id), ids, 'Pagination must not lose late-dated messages');
  await source.acknowledge(ids.at(-1));
  assert.deepEqual(await source.read(), []);
  assert.equal(fixture.sent.length, 1);
  assert.equal(fixture.sent[0].chatGuid, 'any;-;allowed@example.test');
  assert.equal(fixture.sent[0].message, 'Task received');
  assert.throws(() => new MessageSource({ ...options, sender: '' }), /sender/);
  for (const chatGuid of ['any;+;allowed@example.test', 'any;-;other@example.test']) {
    assert.throws(() => new MessageSource({ ...options, chatGuid }), /direct chat/);
  }
  fixture.leak = { ...fixture.rows.find(row => row.handle.address === 'other@example.test'), originalROWID: ids.at(-1) + 1 };
  await assert.rejects(source.read(), /outside the configured sender scope/);
  fixture.leak = null;
  fixture.sendError = 401;
  await assert.rejects(source.send('Must not claim delivery'), /HTTP 401/);
  assert.equal(fixture.sent.length, 1);
  fixture.sendError = null;
  t.mock.timers.enable({ apis: ['Date'], now: Date.now() });
  await source.send('Expired reply');
  t.mock.timers.tick(24 * 60 * 60 * 1000 + 1);
  const expired = await source.read();
  assert.deepEqual(expired.map(message => message.text), ['Expired reply'], 'Expired credits no longer suppress matching text');
  await source.acknowledge(expired.at(-1).id);
});
