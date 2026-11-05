import test from 'node:test';
import assert from 'node:assert/strict';
import { learnReadout, readCurrent } from '../readout.mjs';

test('A learned fixed field reads the new value and refuses missing or ambiguous fields', () => {
  const screen = { elements: [
    { ref: 'e124', role: 'StaticText', label: '电池健康', trait_names: ['Header'] },
    { ref: 'e127', role: 'StaticText', label: '最大容量、90%', trait_names: [] },
  ] };
  const readout = learnReadout({ kind: 'field', items: [{ ref: 'e127', field: 'label', prefix: '最大容量、', suffix: '%' }] }, screen);
  assert.deepEqual(readCurrent(readout, screen).details, [{ label: '最大容量', value: '90%' }]);
  const updated = { elements: [screen.elements[0], { ...screen.elements[1], ref: 'e200', label: '最大容量、89%' }] };
  assert.deepEqual(readCurrent(readout, updated).details, [{ label: '最大容量', value: '89%' }]);
  assert.equal(readCurrent(readout, { elements: [updated.elements[0]] }), null);
  assert.equal(readCurrent(readout, { elements: [...updated.elements, { ...updated.elements[1], ref: 'e201' }] }), null);
  const separate = { elements: [{ ref: 'e1', role: 'TextField', label: 'Capacity', value: '90%' }] };
  const valueReadout = learnReadout({ kind: 'field', items: [{ ref: 'e1', field: 'value' }] }, separate);
  assert.equal(readCurrent(valueReadout, { elements: [{ ...separate.elements[0], value: '' }] }), null);
  assert.equal(readCurrent(valueReadout, { elements: [{ ...separate.elements[0], value: '89%' }] }).details[0].value, '89%');
});
