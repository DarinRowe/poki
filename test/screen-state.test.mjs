import test from 'node:test';
import assert from 'node:assert/strict';
import { describeScreen, promptWarning } from '../src/interaction.mjs';

test('purchase detection keeps ordinary text and shop controls usable', () => {
  for (const label of ['香港购买 iPhone 攻略', '購買紀錄', 'How to confirm with side button', '确认购买']) {
    assert.equal(promptWarning([{ role: 'StaticText', label }, { role: 'Button', label: '购买' }]), null, label);
  }
  assert.deepEqual(promptWarning(['確認購買', '確定', '取消'].map(text => ({ text }))), { kind: 'purchase' });
  for (const text of ['Double-click to Pay', 'Double-click to Install', 'Confirm with Side Button', '連 按 兩 下 以 購 買']) {
    assert.deepEqual(promptWarning([{ text }]), { kind: 'purchase' }, text);
  }
});

test('the system passcode screen identifies a locked device, while app passcode fields do not', () => {
  const elements = [
    { role: 'StaticText', label: 'Enter Passcode', visible: true },
    { role: 'SecureTextField', label: 'Passcode field', visible: true },
  ];
  const screen = bundle_id => describeScreen({ foreground: { bundle_id }, elements });
  assert.equal(screen('com.apple.springboard').device_state, 'locked');
  assert.equal(screen('com.example.settings').device_state, undefined);
  assert.equal(describeScreen({ foreground: { bundle_id: 'com.apple.springboard' }, elements: [] }).device_state, undefined);
  assert.equal(describeScreen({ foreground: { bundle_id: 'com.apple.springboard' }, elements }, elements, 'ocr').device_state, undefined);
});
