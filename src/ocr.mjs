import sharp from 'sharp';
import { checkWork, execute } from './work.mjs';
const languagesByInstall = new Map();

export async function tesseractLanguages(binary, dataDir, configured) {
  if (configured) return configured;
  const key = JSON.stringify([binary, dataDir ?? null]);
  const cached = languagesByInstall.get(key);
  if (cached) return cached;
  const args = [...(dataDir ? ['--tessdata-dir', dataDir] : []), '--list-langs'];
  try {
    const { stdout } = await execute(binary, args, { timeout: 1000, maxBuffer: 64 * 1024 });
    const installed = new Set(stdout.split(/\r?\n/).map(line => line.trim()));
    const languages = ['eng', ...['chi_sim', 'chi_tra'].filter(language => installed.has(language))].join('+');
    languagesByInstall.set(key, languages);
    return languages;
  } catch {
    checkWork();
    return 'eng';
  }
}

// Tesseract TSV coordinates, like Vision's output, are image pixels.
export function parseTesseractTSV(tsv) {
  const lines = tsv.trimEnd().split(/\r?\n/);
  if (!lines[0]?.startsWith('level\tpage_num\t')) throw new Error('Invalid Tesseract TSV output');
  const groups = new Map();
  for (const line of lines.slice(1)) {
    const cells = line.split('\t');
    if (cells.length < 12 || cells[0] !== '5') continue;
    const [x, y, width, height, confidence] = cells.slice(6, 11).map(Number);
    const text = cells.slice(11).join('\t').trim();
    if (!text || ![x, y, width, height, confidence].every(Number.isFinite) || x < 0 || y < 0 || width <= 0 || height <= 0 || confidence < 0 || confidence > 100) continue;
    const key = cells.slice(1, 5).join(':');
    let group = groups.get(key);
    if (!group) { group = { words: [], x, y, right: x + width, bottom: y + height, score: 0 }; groups.set(key, group); }
    group.words.push(text); group.x = Math.min(group.x, x); group.y = Math.min(group.y, y);
    group.right = Math.max(group.right, x + width); group.bottom = Math.max(group.bottom, y + height); group.score += confidence;
  }
  return [...groups.values()].map(g => ({ text: g.words.join(' '), confidence: g.score / g.words.length / 100, x: g.x, y: g.y, width: g.right - g.x, height: g.bottom - g.y }));
}

// Ignore the status and home-indicator bands. A small grayscale image lets
// nearby layouts share timing history without another accessibility read.
export async function ocrPageDescriptor(frame) {
  const inset = Math.floor(frame.height * 0.05);
  const pixels = await sharp(frame.data)
    .extract({ left: 0, top: inset, width: frame.width, height: frame.height - 2 * inset })
    .resize(24, 32, { fit: 'fill' })
    .greyscale().removeAlpha().raw().toBuffer();
  return { key: JSON.stringify([frame.device, frame.width, frame.height]), pixels };
}
