const sentences = new Intl.Segmenter(undefined, { granularity: 'sentence' });

export function openingSentence(text) {
  if (typeof text !== 'string') return '';
  return sentences.segment(text.replace(/\s+/g, ' ').trim())[Symbol.iterator]().next().value?.segment.trim() ?? '';
}

export function openingFromPrompt(prompt) {
  const task = openingSentence(prompt).replace(/[.!?。！？]+$/u, '');
  if (/\p{Script=Han}/u.test(task)) return `我会${task.replace(/^(?:麻烦你|请你|请)?(?:帮我|替我|为我)?/u, '')}。`;
  return `I'll work on "${task}".`;
}
