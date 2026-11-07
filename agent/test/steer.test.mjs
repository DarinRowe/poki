import test from 'node:test';
import assert from 'node:assert/strict';
import { runnerFixture } from './fixtures/runner.mjs';

const summary = "Stopped at the user's request.";
const isVerification = request => request.tools?.some(tool => tool.name === 'report_verification');

async function stopRequestedMidTask(t) {
  let runner;
  let steered = false;
  const fixture = await runnerFixture(t, {
    route: false,
    execution: [
      ['report_plan', { title: 'Local fixture task', steps: ['Read the fixture'], currentStep: 1 }],
      ['list_elements', {}],
      ['finish_task', { success: false, summary, details: [], answer: { kind: 'action' } }],
    ],
    beforeDeviceCall: async name => {
      if (name !== 'list_elements' || steered) return;
      steered = true;
      await runner.receive({ id: 'steer', text: 'please stop now' });
    },
  });
  runner = fixture.runner;
  t.mock.timers.enable({ apis: ['setTimeout'] });
  await runner.receive({ id: 'task', text: 'Read the fixture status.' });
  await Promise.resolve();
  t.mock.timers.tick(3000);
  await runner.finished;
  t.mock.timers.reset();
  assert.ok(steered, 'The stop request arrived while the task was running');
  assert.ok(fixture.services.modelRequests.some(request => !isVerification(request) && JSON.stringify(request.input).includes('The user added: please stop now')),
    'The task model received the stop request before finishing');
  assert.equal(runner.task.snapshot.phase, 'failed');
  assert.equal(runner.task.snapshot.result, summary);
  return fixture;
}

test('A message sent during a task reaches result verification of the stopped task', { timeout: 30000 }, async t => {
  const { services } = await stopRequestedMidTask(t);
  const verification = services.modelRequests.find(isVerification);
  assert.ok(verification, 'The failure claim was verified');
  assert.ok(JSON.stringify(verification.input).includes('please stop now'), 'The verifier sees what the user asked during the task');
});

test('A message sent during a task is acknowledged with how to stop it', { timeout: 30000 }, async t => {
  const { replies } = await stopRequestedMidTask(t);
  const hint = replies.findIndex(text => text.includes('/stop'));
  assert.ok(hint > 0 && hint < replies.indexOf(summary), `The /stop hint arrives after the opening and before the result: ${JSON.stringify(replies)}`);
});
