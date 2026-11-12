import test from 'node:test';
import assert from 'node:assert/strict';
import { pairedText, tokenUsage, toolWallTime } from '../bin/eval-first-call.mjs';

test('paired arms share input and separate rounds vary it', () => {
  const job = { task: 'focus', client: 'codex', round: 1 };
  assert.equal(pairedText({ ...job, group: 'before' }), pairedText({ ...job, group: 'after' }));
  assert.notEqual(pairedText(job), pairedText({ ...job, round: 2 }));
});

test('token accounting preserves provider cache semantics and missing usage', () => {
  const expected = { input: 120, cached_input: 80, uncached_input: 40, output: 10, total: 130 };
  assert.deepEqual(tokenUsage('codex', { input_tokens: 120, cached_input_tokens: 80, output_tokens: 10 }), expected);
  assert.deepEqual(tokenUsage('claude', { input_tokens: 30, cache_read_input_tokens: 80, cache_creation_input_tokens: 10, output_tokens: 10 }), expected);
  assert.equal(tokenUsage('codex', { input_tokens: 120, output_tokens: 10 }).uncached_input, null);
  assert.equal(tokenUsage('codex', null), null);
});

test('tool wall time only counts overlapping intervals once', () => {
  assert.equal(toolWallTime([
    { startedAt: 20, endedAt: 25 }, { startedAt: 0, endedAt: 10 },
    { startedAt: 5, endedAt: 15 }, { startedAt: 25 },
  ]), 20);
});
