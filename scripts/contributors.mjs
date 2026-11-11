#!/usr/bin/env node
// Rebuild the contributor list from GitHub data, and keep the README
// "Core contributors" wall in step with it.
//
//   node scripts/contributors.mjs                      report: counted, pending, new
//   node scripts/contributors.mjs --out-dir <dir>      also write contributors.json and contributors.md there
//   node scripts/contributors.mjs --check              exit 1 if someone qualifies but is not on the wall
//   node scripts/contributors.mjs --write-readme       rewrite the core wall and the thanks wall in all six READMEs from scripts/contributors.curated.json
//
// Statuses in the curated file: counted (core wall), community (thanks wall and the JSON,
// early feedback and attempts), pending (undecided), excluded (not a contribution).
//
// Facts (who, which PRs and issues, first date) come from `gh api`.
// Judgement (counted, pending, excluded, the one-line summary per language)
// lives in scripts/contributors.curated.json and is edited by a person.
// Requires an authenticated GitHub CLI (gh). Read-only on GitHub.
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = 'JosssphZhou/poki';
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const curatedPath = join(root, 'scripts/contributors.curated.json');
const readmes = { en: 'README.md', 'zh-CN': 'README.zh-CN.md', 'zh-TW': 'README.zh-TW.md', ja: 'README.ja.md', ko: 'README.ko.md', es: 'README.es.md' };
const start = '<!-- CORE-CONTRIBUTORS:START -->';
const end = '<!-- CORE-CONTRIBUTORS:END -->';
const perRow = 3;

const usage = `Usage: node scripts/contributors.mjs [--out-dir <dir>] [--check] [--write-readme]`;

function gh(path) {
  const result = spawnSync('gh', ['api', '--paginate', '--slurp', path], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw new Error(`gh api ${path} failed: ${(result.stderr || result.error?.message || '').trim()}`);
  return JSON.parse(result.stdout).flat();
}

const isBot = user => !user || user.type === 'Bot' || user.login.endsWith('[bot]');
const day = iso => iso.slice(0, 10);

// What GitHub knows about each person, before anyone decides who counts.
function collect() {
  const owner = JSON.parse(spawnSync('gh', ['api', `repos/${repo}`], { encoding: 'utf8' }).stdout).owner.login;
  const pulls = gh(`repos/${repo}/pulls?state=all&per_page=100`);
  const issues = gh(`repos/${repo}/issues?state=all&per_page=100`).filter(item => !item.pull_request);
  const comments = gh(`repos/${repo}/issues/comments?per_page=100`);
  const commits = gh(`repos/${repo}/commits?sha=main&per_page=100`);

  const people = new Map();
  const person = user => {
    if (!people.has(user.login)) people.set(user.login, { login: user.login, profile: user.html_url, avatar: user.avatar_url, mergedPulls: [], otherPulls: [], issues: [], commits: 0, coAuthored: 0, first: null });
    return people.get(user.login);
  };
  const seen = (p, iso) => { if (iso && (!p.first || iso < p.first)) p.first = iso; };

  // A merged pull request that says "Fixes #N" shows the report led to a change.
  const closedBy = new Map();
  for (const pull of pulls.filter(p => p.merged_at))
    for (const match of `${pull.title}\n${pull.body ?? ''}`.matchAll(/\b(?:fix(?:e[sd])?|close[sd]?|resolve[sd]?)\s+#(\d+)/gi))
      closedBy.set(Number(match[1]), pull.number);
  const ownerFixed = new Set(comments
    .filter(c => c.user.login === owner && /\b(?:on main|is merged|now merged|fix(?:ed)? (?:is|in)|landed|merged into)\b/i.test(c.body))
    .map(c => Number(c.issue_url.split('/').pop())));

  for (const pull of pulls) {
    if (isBot(pull.user) || pull.user.login === owner) continue;
    const p = person(pull.user);
    seen(p, pull.created_at);
    (pull.merged_at ? p.mergedPulls : p.otherPulls).push({ number: pull.number, state: pull.state, opened: day(pull.created_at), title: pull.title });
  }
  for (const issue of issues) {
    if (isBot(issue.user) || issue.user.login === owner) continue;
    const p = person(issue.user);
    seen(p, issue.created_at);
    p.issues.push({ number: issue.number, state: issue.state, opened: day(issue.created_at), title: issue.title, ledToFix: closedBy.has(issue.number) || (issue.state_reason === 'completed' && ownerFixed.has(issue.number)) });
  }
  for (const commit of commits) {
    if (isBot(commit.author) || commit.author.login === owner) continue;
    const p = person(commit.author);
    p.commits += 1;
    seen(p, commit.commit.author.date);
  }
  // Co-authored-by trailers with a GitHub noreply address name a login too.
  for (const commit of commits)
    for (const match of commit.commit.message.matchAll(/^co-authored-by:.*<\d+\+([^@>]+)@users\.noreply\.github\.com>/gim)) {
      const p = people.get(match[1]);
      if (p) { p.coAuthored += 1; seen(p, commit.commit.author.date); }
    }
  return { owner, people: [...people.values()] };
}

function wallLogins(file = readmes.en) {
  const text = readFileSync(join(root, file), 'utf8');
  const from = text.indexOf(start);
  const block = from === -1 ? text.slice(text.search(/^## Core contributors/m)) : text.slice(from, text.indexOf(end, from));
  return [...block.matchAll(/<a href="https:\/\/github\.com\/([A-Za-z0-9-]+)"><img/g)].map(m => m[1]).filter((v, i, a) => a.indexOf(v) === i);
}

function classify(people, curated, onWall) {
  const rows = people.map(p => {
    const entry = curated[p.login];
    const signals = [];
    if (p.mergedPulls.length) signals.push(`merged ${p.mergedPulls.map(x => `#${x.number}`).join(' ')}`);
    if (p.commits && !p.mergedPulls.length) signals.push(`${p.commits} commits on main`);
    for (const i of p.issues.filter(i => i.ledToFix)) signals.push(`report led to a fix #${i.number}`);
    const auto = signals.length ? 'counted' : 'pending';
    return { ...p, auto, signals, status: entry?.status ?? null, reviewed: Boolean(entry), onWall: onWall.has(p.login), entry };
  });
  const byFirst = (a, b) => (a.first ?? '').localeCompare(b.first ?? '') || a.login.localeCompare(b.login);
  const counted = rows.filter(r => (r.status ?? r.auto) === 'counted').sort(byFirst);
  return {
    counted,
    community: rows.filter(r => r.status === 'community').sort(byFirst),
    pending: rows.filter(r => (r.status ?? r.auto) === 'pending').sort(byFirst),
    excluded: rows.filter(r => r.status === 'excluded').sort(byFirst),
    unreviewed: rows.filter(r => !r.reviewed).sort(byFirst),
    missingFromWall: counted.filter(r => !r.onWall),
  };
}

const categories = { code: 'Code', report: 'Bug report', testing: 'Testing', docs: 'Docs', design: 'Design' };
const label = r => (r.entry?.categories ?? []).map(c => categories[c] ?? c).join(', ') || '-';
const link = n => `[#${n}](https://github.com/${repo}/issues/${n})`;

function markdown(result, generated) {
  const line = r => `| [${mdName(r)}](${r.profile}) | ${r.entry?.summary ?? '(no summary yet)'} | ${(r.entry?.basis ?? []).map(n => /^#\d+$/.test(n) ? link(n.slice(1)) : n).join(' ')} | ${r.first ? day(r.first) : '-'} | ${label(r) } |`;
  const head = '| GitHub user | What they did | Basis | First contribution | Category |\n| --- | --- | --- | --- | --- |';
  const out = [`# Poki contributors (generated ${generated})`, '', `## Counted (${result.counted.length})`, '', head, ...result.counted.map(line)];
  out.push('', `## Community, early feedback and attempts (${result.community.length})`, '', head, ...result.community.map(line));
  out.push('', `## Pending a decision, 待主控定 (${result.pending.length})`, '', '| GitHub user | Activity | Why it is not counted yet |', '| --- | --- | --- |');
  for (const r of result.pending) out.push(`| [${mdName(r)}](${r.profile}) | ${activity(r)} | ${r.entry?.note ?? 'no signal that a change followed'} |`);
  return `${out.join('\n')}\n`;
}

function activity(r) {
  return [...r.issues.map(i => `issue #${i.number} (${i.state})`), ...r.otherPulls.map(x => `PR #${x.number} (${x.state})`), ...r.mergedPulls.map(x => `PR #${x.number} (merged)`)].join(', ');
}

// ---- README wall -------------------------------------------------------

const escapeAttr = s => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/\*/g, '&#42;');
// An entry can set "display" to show a different name than the GitHub login. Links still use the login.
const shownName = r => r.entry?.display ?? r.login;
const mdName = r => shownName(r).replace(/\*/g, '\\*');
function refKind(people) {
  const kinds = new Map();
  for (const p of people) {
    for (const x of [...p.mergedPulls, ...p.otherPulls]) kinds.set(x.number, 'pull');
    for (const i of p.issues) kinds.set(i.number, 'issues');
  }
  return kinds;
}
function renderLine(text, kinds) {
  return text.replace(/#(\d+)/g, (_, n) => `<a href="https://github.com/${repo}/${kinds.get(Number(n)) ?? 'issues'}/${n}">#${n}</a>`);
}
function renderWall(rows, language, kinds) {
  const cells = rows.map(r => {
    const name = escapeAttr(shownName(r));
    const text = r.entry.lines[language] ?? r.entry.lines.en;
    const avatar = new URL(r.avatar); avatar.searchParams.set('size', '240');
    return `<td align="center" valign="top" width="33%"><a href="${r.profile}"><img src="${avatar}" width="120" height="120" alt="${name}"/><br /><sub><b>${name}</b></sub></a><br />${renderLine(text, kinds)}</td>`;
  });
  const rowsHtml = [];
  for (let i = 0; i < cells.length; i += perRow) rowsHtml.push(`    <tr>\n      ${cells.slice(i, i + perRow).join('\n      ')}\n    </tr>`);
  return `\n<table>\n  <tbody>\n${rowsHtml.join('\n')}\n  </tbody>\n</table>\n`;
}
function injectWall(text, block, file) {
  const from = text.indexOf(start);
  const to = text.indexOf(end, from);
  if (from === -1 || to === -1) throw new Error(`${file} is missing the ${start} ... ${end} markers.`);
  return text.slice(0, from + start.length) + block + text.slice(to);
}

// ---- main --------------------------------------------------------------

const args = process.argv.slice(2);
const flag = name => args.includes(name);
const outDir = args.includes('--out-dir') ? args[args.indexOf('--out-dir') + 1] : null;
if (flag('--help') || flag('-h') || args.some(a => a.startsWith('--') && !['--out-dir', '--check', '--write-readme'].includes(a))) {
  console.log(usage);
  process.exit(flag('--help') || flag('-h') ? 0 : 1);
}

try {
  const curated = JSON.parse(readFileSync(curatedPath, 'utf8'));
  const { people } = collect();
  const result = classify(people, curated, new Set(wallLogins()));
  const generated = new Date().toISOString().slice(0, 10);

  if (outDir) {
    mkdirSync(outDir, { recursive: true });
    const view = r => ({ login: r.login, display: shownName(r), profile: r.profile, avatar: r.avatar, status: r.status ?? r.auto, categories: r.entry?.categories ?? [], summary: r.entry?.summary ?? null, basis: r.entry?.basis ?? [], first_contribution: r.first ? day(r.first) : null, on_readme_wall: r.onWall, signals: r.signals, note: r.entry?.note ?? null });
    writeFileSync(join(outDir, '贡献者名单.json'), `${JSON.stringify({ repo, generated, counted: result.counted.map(view), community: result.community.map(view), pending: result.pending.map(view), excluded: result.excluded.map(view) }, null, 2)}\n`);
    writeFileSync(join(outDir, '贡献者名单.md'), markdown(result, generated));
  }

  if (flag('--write-readme')) {
    const rows = result.counted.filter(r => r.entry?.lines);
    const missing = result.counted.filter(r => !r.entry?.lines).map(r => r.login);
    if (missing.length) throw new Error(`No README lines yet for: ${missing.join(', ')}`);
    const kinds = refKind(people);
    const changed = [];
    for (const [language, file] of Object.entries(readmes)) {
      const path = join(root, file);
      const before = readFileSync(path, 'utf8');
      const after = injectWall(before, renderWall(rows, language, kinds), file);
      if (before !== after) { writeFileSync(path, after); changed.push(file); }
    }
    console.log(changed.length ? `Updated ${changed.join(', ')}` : 'README walls already up to date.');
    // The thanks wall draws from the same curated file.
    const thanks = spawnSync(process.execPath, [join(root, 'bin/thanks-wall.mjs')], { encoding: 'utf8' });
    process.stdout.write(thanks.stdout); process.stderr.write(thanks.stderr);
    if (thanks.status !== 0) throw new Error('bin/thanks-wall.mjs failed.');
  }

  const names = list => list.map(r => r.login).join(', ') || 'none';
  console.log(`Counted ${result.counted.length}. On the README wall: ${result.counted.filter(r => r.onWall).length}.`);
  console.log(`New (counted, not on the wall): ${names(result.missingFromWall)}`);
  console.log(`Not reviewed yet (not in contributors.curated.json): ${names(result.unreviewed)}`);
  console.log(`Pending a decision: ${names(result.pending)}`);
  if (flag('--check')) {
    const thanks = spawnSync(process.execPath, [join(root, 'bin/thanks-wall.mjs'), '--check'], { encoding: 'utf8' });
    process.stdout.write(thanks.stdout); process.stderr.write(thanks.stderr);
    if (result.missingFromWall.length || result.unreviewed.length || thanks.status !== 0) process.exit(1);
  }
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
