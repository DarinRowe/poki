import test from 'node:test';
import assert from 'node:assert/strict';
import { StepDeadline } from '../step-deadline.mjs';
const screen = (heading, value = '') => ({ foreground: { bundle_id: 'fixture' }, elements: [
  { role: 'Heading', label: heading }, { role: 'TextField', value },
] });

test('Same-page attempts expire; progressing steps and pages can run beyond 60 seconds', t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] });
  let failures = 0;
  const stuck = new StepDeadline(60, () => failures++);
  stuck.start(); stuck.advance(1); stuck.observe(screen('Editor'), { tool: 'tap' });
  t.mock.timers.tick(40000);
  stuck.observe({ ...screen('Paste permission'), elements: [...screen('Paste permission').elements, { role: 'Alert' }] }, { tool: 'tap' });
  stuck.observe(screen('Editor', 'new text'), { tool: 'tap' }); stuck.advance(1); stuck.advance(0);
  t.mock.timers.tick(20000);
  assert.equal(failures, 1, 'Same-page activity must not renew the deadline');
  const progressing = new StepDeadline(60, () => failures++);
  progressing.start(); progressing.advance(1); progressing.observe(screen('Home'), { tool: 'tap' });
  t.mock.timers.tick(50000); progressing.advance(2);
  t.mock.timers.tick(50000); progressing.observe(screen('Settings'), { tool: 'tap' });
  t.mock.timers.tick(50000);
  assert.equal(failures, 1, '150 seconds of progress must not hit a whole-task timeout');
  progressing.observe(screen('Settings', 'changed'), { tool: 'tap' });
  t.mock.timers.tick(10000);
  assert.equal(failures, 2);
});

test('Scrolling or swiping new text into view cannot renew the same page deadline', t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] });
  for (const action of [{ tool: 'scroll' }, { tool: 'swipe' }, { tool: 'batch_commands', arguments: { commands: [{ tool: 'scroll' }, { tool: 'swipe' }] } }, { tool: 'batch_commands', arguments: { commands: [{ tool: 'launch_app' }, { tool: 'scroll' }, { tool: 'list_elements' }] } }]) {
    let expired = false;
    const deadline = new StepDeadline(60, () => { expired = true; });
    deadline.start(); deadline.observe(screen('Raspberry Pi', 'Top'), false);
    t.mock.timers.tick(40000);
    deadline.observe(screen('Compute Module 5', 'Next section'), action);
    t.mock.timers.tick(20000);
    assert.equal(expired, true, `${action.tool} changes visible text, not the page`);
  }
});

test('Chrome screens without headings renew only after successful navigation, not same-page attempts', t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] });
  const edits = value => ({ foreground: { bundle_id: null, name: 'Chrome' }, elements: [
    { role: 'Application', label: 'Chrome', ref: 'e1' },
    { role: 'TextField', label: '地址和搜索栏', value, ref: 'e2', focused: true },
    { role: 'Button', label: '取消', ref: 'e3' },
  ] });
  const results = { foreground: { bundle_id: null, name: 'Chrome' }, elements: [
    { role: 'Application', label: 'Chrome', ref: 'e40' },
    { role: 'Button', label: '地址和搜索栏', value: 'google.com 安全', ref: 'e41' },
    { role: 'TextField', label: 'Google 搜索', value: 'esp32', ref: 'e42' },
    { role: 'Link', label: 'ESP32 Wi-Fi & Bluetooth SoC', ref: 'e43' },
  ] };
  let expired = 0;
  const records = [];
  const deadline = new StepDeadline(30, () => expired++, record => records.push(record));
  deadline.start(); deadline.advance(1); deadline.observe(edits(''), false);
  t.mock.timers.tick(25000);
  deadline.observe({ content: [{ type: 'text', text: JSON.stringify({ completed_steps: 2, screen: {
    foreground: 'Chrome', text: ['Application: Chrome', 'Button: 地址和搜索栏 = google.com 安全', 'TextField: Google 搜索 = esp32', 'Link: ESP32 Wi-Fi & Bluetooth SoC'],
  } }) }] }, { tool: 'tap' });
  t.mock.timers.tick(6000);
  assert.equal(expired, 0, 'A successful search submission must receive a new 30-second window');
  assert.ok(records.some(record => record.endReason === 'new_page' && record.page));
  const same = structuredClone(results);
  same.elements.forEach((element, i) => { element.ref = `e${i + 80}`; element.frame = { x: 0, y: 10 + i, width: 200, height: 20 }; element.focused = false; });
  same.elements[2].value = 'another spelling';
  deadline.observe(same, { tool: 'tap' });
  t.mock.timers.tick(24000);
  assert.equal(expired, 1, 'Same-page attempts must not extend the navigation window');
});
