import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { RouteStore } from '../routes.mjs';
import { conditionsMatch } from '../fast/task.mjs';

test('A repeated city label preserves the verified header when learning and reading a route', async t => {
  const sample = JSON.parse(await readFile(new URL('./fixtures/luma-route.json', import.meta.url), 'utf8'));
  sample.details = sample.details.slice(1).map(detail => ({ label: detail.value, value: '' }));
  const directory = await mkdtemp(join(tmpdir(), 'poki-route-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const store = new RouteStore(directory);
  const context = 'Read only. Do not register, sign in, send messages, or change settings.';
  const answer = { kind: 'list', start_ref: 'e51', end_ref: 'e55', items: ['e52', 'e53', 'e54'].map(ref => ({ ref, field: 'label' })) };
  const learned = await store.learn({ ...sample, answer, context, id: 'recorded-luma-task', device: 'recorded-physical-device', verify: async () => true });
  assert.ok(learned, 'The verified city header must remain identifiable beside the city card');
  assert.equal(await store.find(sample.prompt), null, 'A route learned with initial restrictions belongs to that scope');
  assert.equal(await store.find(sample.prompt, 'Only inspect the first event'), null, 'Changed restrictions must explore again');
  const route = await store.find(sample.prompt, context);
  const final = sample.trace.at(-1).result;
  assert.ok(conditionsMatch(route.plan.success, final));
  const changed = { elements: final.elements.map(e => e.label?.startsWith('Molecular World Models:')
    ? { ...e, label: 'New Astronomy Talk, Tomorrow, 18:30 GMT-8' } : e) };
  assert.ok(conditionsMatch(route.plan.success, changed), 'Navigation reaches the current result page even when its list content changes');
  const current = store.readResult(route, changed);
  assert.ok(current.summary.includes('New Astronomy Talk, Tomorrow, 18:30 GMT-8'));
  assert.ok(!current.summary.includes('Molecular World Models:'), 'Never replay the old activity name or time');
  const loading = { elements: changed.elements.map(e => e.ref === 'e52' ? { ...e, label: 'Loading' } : e) };
  assert.equal(store.readResult(route, loading), null, 'An activity without the learned time structure needs model inspection');
  const withoutHeader = { elements: final.elements.filter(e => !(e.label === '洛杉矶' && e.trait_names?.includes('Header'))) };
  assert.equal(conditionsMatch(route.plan.success, withoutHeader), false, 'A city card cannot replace the current-city header');

  const actionPrompt = 'Open the Luma Discover page.';
  await store.learn({ ...sample, details: [{ label: 'Page', value: '热门活动' }], prompt: actionPrompt, answer: { kind: 'action' }, id: 'navigation-action', device: 'recorded-physical-device', verify: async () => true });
  const action = await store.find(actionPrompt);
  assert.equal(store.readResult(action, final).success, true);
  assert.equal(store.readResult(action, withoutHeader), null, 'An action is successful only while its result conditions match');
});
