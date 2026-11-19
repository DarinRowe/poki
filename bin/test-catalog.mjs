#!/usr/bin/env node
// Integrated test-scenario catalog. One place that inventories every automated and manual test
// scenario in this repository, runs the suites this machine can run, and records the metrics that
// matter for judging what Poki can do: scenario counts, pass/fail/timeout, wall time, per-capability
// coverage and tool coverage.
//
//   node bin/test-catalog.mjs                # inventory + run the Node suites and the action-efficiency scenarios
//   node bin/test-catalog.mjs --static       # inventory only; runs nothing
//   node bin/test-catalog.mjs --rust         # also run the desktop Rust workspace tests
//   node bin/test-catalog.mjs --no-eval      # skip the action-efficiency scenarios
//   node bin/test-catalog.mjs --out docs     # where test-scenarios.md and test-scenarios.json go
//
// Outputs (both overwritten on every run):
//   docs/test-scenarios.md    the catalog for people (Chinese, test names left in their source form)
//   docs/test-scenarios.json  the same data as JSON, for scripts and trend comparisons
// Appends one compact record per run to .runtime/test-catalog/history.jsonl (git-ignored).
//
// Suites that need Xcode, an iOS simulator, a phone or a model account are inventoried from the
// source and reported as "not run here"; run them where their hardware and account live.
import { spawn, execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { appendFile, mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const CAPS = {
  observe: { zh: '观察', hint: '读屏 / 元素树 / 截图 / OCR / AX' },
  act: { zh: '操作', hint: '点击 / 输入 / 手势 / 滚动 / 按键' },
  batch: { zh: '批量与等待', hint: '批量动作 / 条件等待 / 回执校验' },
  session: { zh: '会话与传输', hint: '协议 / 鉴权 / 租约 / 守护进程 / 连接恢复' },
  install: { zh: '安装与配对', hint: 'Setup / 配对 / 签名 / 更新' },
  agent: { zh: 'Agent 端', hint: '任务运行器 / 渠道 / 模型交互' },
  safety: { zh: '安全与审批', hint: '审批 / 输入锁 / 危险操作' },
  stability: { zh: '稳定性与容错', hint: 'soak / 超时 / 中断 / 恢复' },
  efficiency: { zh: '效率与资源', hint: '耗时 / 调用数 / 内存 / CPU' },
  diagnostics: { zh: '诊断与证据', hint: '日志 / 录制 / 回放 / 截图证据' },
};

const MAIN_FILE_TAGS = {
  'test/ax-viewport.test.mjs': ['observe', 'act'],
  'test/batch-device-choice.test.mjs': ['batch', 'session'],
  'test/batch-input-recovery.test.mjs': ['batch', 'stability'],
  'test/call-log.test.mjs': ['diagnostics'],
  'test/conditional-actions.test.mjs': ['batch'],
  'test/coordination.test.mjs': ['session', 'batch'],
  'test/cua-wda.test.mjs': ['act', 'observe'],
  'test/cua.test.mjs': ['act', 'observe'],
  'test/default-device.test.mjs': ['session'],
  'test/draw.test.mjs': ['act'],
  'test/eval-metrics.test.mjs': ['efficiency', 'diagnostics'],
  'test/input-lock.test.mjs': ['safety'],
  'test/install-download.test.mjs': ['install'],
  'test/install-iphone.test.mjs': ['install', 'stability'],
  'test/install-model-key.test.mjs': ['install'],
  'test/install-records.test.mjs': ['install', 'diagnostics'],
  'test/native-session.test.mjs': ['session'],
  'test/observation-output.test.mjs': ['observe', 'batch'],
  'test/observation.test.mjs': ['observe'],
  'test/ocr.test.mjs': ['observe'],
  'test/post-action-do-rotation.test.mjs': ['observe', 'act'],
  'test/post-action-observation.test.mjs': ['observe'],
  'test/prepare-device.test.mjs': ['install'],
  'test/prepare-remote.test.mjs': ['install'],
  'test/protocol.test.mjs': ['session', 'safety'],
  'test/remote.test.mjs': ['session'],
  'test/run-code.test.mjs': ['act'],
  'test/save-screenshot.test.mjs': ['diagnostics', 'observe'],
  'test/scroll-container.test.mjs': ['act', 'observe'],
  'test/setup-app-channel.test.mjs': ['install'],
  'test/simulator-orientation.test.mjs': ['act'],
  'test/terminate-app.test.mjs': ['act'],
  'test/update.test.mjs': ['install'],
  'test/vision-ocr.test.mjs': ['observe'],
  'test/voice-bridge.test.mjs': ['act', 'safety'],
};

const AGENT_FILE_TAGS = {
  'agent/test/agent-observation-reuse.test.mjs': ['observe', 'batch', 'efficiency'],
  'agent/test/channels.test.mjs': ['agent'],
  'agent/test/fast-observation-reuse.test.mjs': ['observe', 'efficiency'],
  'agent/test/gateway-setup.test.mjs': ['agent', 'install'],
  'agent/test/learned-route.test.mjs': ['agent'],
  'agent/test/messages.test.mjs': ['agent'],
  'agent/test/openai.test.mjs': ['agent'],
  'agent/test/opening.test.mjs': ['agent'],
  'agent/test/poki-cli.test.mjs': ['agent'],
  'agent/test/post-action-observation.test.mjs': ['observe'],
  'agent/test/readout.test.mjs': ['agent', 'diagnostics'],
  'agent/test/route-answer.test.mjs': ['agent', 'act'],
  'agent/test/routes.test.mjs': ['agent'],
  'agent/test/self-chat.test.mjs': ['agent'],
  'agent/test/steer.test.mjs': ['agent'],
  'agent/test/step-timeout-cli.test.mjs': ['agent', 'stability'],
  'agent/test/step-timeout.test.mjs': ['agent', 'stability'],
  'agent/test/telegram.test.mjs': ['agent'],
  'agent/test/tool-timeout.test.mjs': ['stability', 'agent'],
  'agent/test/unlock-device.test.mjs': ['safety', 'install'],
  'agent/test/verification-trace.test.mjs': ['observe', 'diagnostics'],
};

const SWIFT_FILE_TAGS = {
  'native/ios/PokiCore/Tests/PokiCoreTests/CoreTests.swift': ['session', 'observe'],
  'native/ios/PokiCore/Tests/PokiCoreTests/FaultTests.swift': ['stability'],
  'native/ios/PokiCore/Tests/PokiCoreTests/HumanizeTests.swift': ['agent'],
  'native/ios/PokiCore/Tests/PokiCoreTests/LookDoTests.swift': ['act', 'observe'],
  'native/ios/PokiCore/Tests/PokiCoreTests/ReconnectTests.swift': ['session', 'stability'],
  'native/ios/PokiCore/Tests/PokiCoreTests/RelaySoakTests.swift': ['session', 'stability', 'efficiency'],
  'native/ios/PokiCore/Tests/PokiCoreTests/RoutineTests.swift': ['agent', 'session'],
  'native/ios/PokiCore/Tests/PokiCoreTests/SoakTests.swift': ['stability', 'efficiency'],
  'native/ios-app/PokiTests/AppModelTests.swift': ['agent', 'install'],
  'native/ios-app/PokiTests/ChatHarnessTests.swift': ['agent'],
  'native/ios-app/PokiTests/HandoffTests.swift': ['agent', 'session'],
  'native/ios-app/PokiTests/InProcessClipboardTests.swift': ['act'],
  'native/ios-app/PokiTests/InProcessSessionTests.swift': ['session'],
  'native/ios-app/PokiTests/VoiceModelTests.swift': ['agent', 'act'],
  'native/ios/PokiLoopback/Tests/PokiLoopbackTests/LoopbackTests.swift': ['session', 'stability'],
};

const RUST_MODULE_TAGS = {
  core: ['install', 'session'],
  cli: ['install', 'agent'],
  bridge: ['session'],
  mac: ['install'],
  app: ['agent'],
};

const GYM_TAGS = {
  animation: ['observe', 'act', 'stability'],
  alert: ['observe', 'act'],
  paste: ['act'],
  list: ['act', 'observe'],
  sheet: ['act'],
  focus: ['act', 'observe'],
  dense: ['observe', 'efficiency'],
  dup: ['observe', 'act'],
  fullscreen: ['observe', 'act'],
  nav: ['act'],
  interrupt: ['stability', 'act'],
  approval: ['safety', 'act'],
};

const EVAL_META = {
  reference: { zh: '计数器：点一次恰好 +1', group: 'development' },
  navigation: { zh: '切页：详情就绪后返回列表', group: 'development' },
  recovery: { zh: '回执丢失：从当前计数继续', group: 'development' },
  interruption: { zh: '滚动中弹窗：关掉后只点指定行', group: 'holdout' },
  focus: { zh: '延迟焦点：保存一次且保留相邻字段', group: 'holdout' },
  canvas: { zh: 'Canvas OCR：按文字定位后点击', group: 'holdout' },
};

const EVAL_TAGS = {
  reference: ['act', 'efficiency'],
  navigation: ['act', 'batch', 'efficiency'],
  recovery: ['stability', 'batch', 'efficiency'],
  interruption: ['act', 'stability', 'efficiency'],
  focus: ['act', 'observe', 'efficiency'],
  canvas: ['observe', 'act', 'efficiency'],
};

const CHECKLIST_TAGS = {
  '0. Before': ['install'],
  '1. Loopback': ['session', 'install'],
  '2. Pairing': ['install', 'session'],
  '3. Launcher': ['install', 'session'],
  '4. PokiCore through the relay': ['session'],
  '5. Approvals': ['safety'],
  '6. Live Activity': ['safety', 'diagnostics'],
};

const PLAYBOOK_TAGS = {
  'docs/verification/cellular-test-plan.md': ['session', 'stability'],
  'docs/verification/lan-bonjour-recovery.md': ['session', 'stability'],
  'docs/verification/tailscale-pr-validation.md': ['session', 'install'],
  'docs/native-ime-testing.md': ['act', 'observe'],
};

const AUTO = { auto: '自动（本机）', simulator: '需 iOS 模拟器', device: '需真机', model: '需模型账号', manual: '人工' };

// Slices of the catalog by how they may be used while developing. This is the anti-overfitting
// backbone: day-to-day changes may only look at the regression and development slices; holdout,
// variant and unseen scenarios are for evaluation days, so a pass there means something.
const SPLITS = {
  regression: { zh: '回归（核心）', use: '日常回归：防止破坏已有行为，改动时随时可看' },
  development: { zh: '开发集', use: '改动时可见，允许反复调参' },
  holdout: { zh: '留出集', use: '只在评估日运行，不得用来调参或挑场景' },
  variant: { zh: '变体（扰动）', use: '替换角色、文案、出现时序，检验是否只记住一种呈现' },
  unseen: { zh: '未见场景（模拟器/真机）', use: '未进入日常循环，检验对真正新界面的泛化' },
  device: { zh: '真机人工', use: '人工判断，覆盖自动化难及的系统界面' },
  acceptance: { zh: '验收脚本', use: '一次性设备验收，不作为日常循环' },
};

const STATE = { pass: '通过', fail: '失败', timeout: '超时', skipped: '跳过', todo: '待办', 'not-run': '未运行', error: '出错' };
const STATE_ICON = { pass: '✅', fail: '❌', timeout: '⏱️', skipped: '⏭️', todo: '📝', 'not-run': '⚪', error: '⚠️' };

const options = parseOptions(process.argv.slice(2));

// ---------------------------------------------------------------------------------------------
// child mode: one test file, in-process isolation, JSON result on stdout
// ---------------------------------------------------------------------------------------------

function parseOptions(argv) {
  const out = { static: false, rust: false, eval: true, render: null, concurrency: 4, timeoutMs: 240000, outDir: 'docs', history: '.runtime/test-catalog/history.jsonl', quiet: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--static') out.static = true;
    else if (arg === '--rust') out.rust = true;
    else if (arg === '--no-eval') out.eval = false;
    else if (arg === '--quiet') out.quiet = true;
    else if (arg === '--concurrency') out.concurrency = Math.max(1, Number(argv[++i]) || 4);
    else if (arg === '--timeout') out.timeoutMs = Math.max(1000, Number(argv[++i]) || 240000);
    else if (arg === '--out') out.outDir = argv[++i] ?? 'docs';
    else if (arg === '--history') out.history = argv[++i] ?? out.history;
    else if (arg === '--render') out.render = argv[++i] ?? 'docs/test-scenarios.json';
    else if (arg.startsWith('--')) throw new Error(`unknown option ${arg}`);
  }
  return out;
}

const round = value => Number.isFinite(Number(value)) ? Math.round(Number(value) * 10) / 10 : 0;
const oneLine = text => String(text ?? '').split('\n').map(line => line.trim()).filter(Boolean).join(' ').trim();
const words = text => String(text ?? '').replace(/([a-z0-9])([A-Z])/g, '$1 $2').replace(/[_\-.:#()/\\]/g, ' ').toLowerCase();
const uniq = list => [...new Set(list)];
const pad = (text, width) => String(text).padEnd(width);
const pct = (part, whole) => whole ? `${Math.round(part / whole * 100)}%` : '—';

function git(...args) {
  try { return execFileSync('git', args, { cwd: ROOT, encoding: 'utf8' }).trim(); } catch { return ''; }
}

function percentile(values, fraction) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil(fraction * sorted.length) - 1));
  return round(sorted[index]);
}

function statusCounts(scenarios) {
  const counts = { pass: 0, fail: 0, timeout: 0, skipped: 0, todo: 0, 'not-run': 0, error: 0 };
  for (const scenario of scenarios) counts[scenario.status] = (counts[scenario.status] ?? 0) + 1;
  return counts;
}

function suiteMetrics(suite) {
  const counts = statusCounts(suite.scenarios);
  const executed = suite.scenarios.filter(s => ['pass', 'fail', 'skipped', 'todo'].includes(s.status));
  const durations = executed.map(s => s.durationMs).filter(value => value > 0);
  const passed = counts.pass;
  return {
    scenarios: suite.scenarios.length,
    executed: executed.length,
    ...counts,
    passRate: executed.length ? round(passed / executed.length * 100) : null,
    durationMs: round(suite.durationMs ?? durations.reduce((a, b) => a + b, 0)),
    medianMs: percentile(durations, 0.5),
    p95Ms: percentile(durations, 0.95),
    maxMs: percentile(durations, 1),
  };
}

// ---------------------------------------------------------------------------------------------
// node suites (main and agent): one child per file, wall-clock timeout per file
// ---------------------------------------------------------------------------------------------

async function main() {
  if (options.render) {
    const catalog = JSON.parse(await readFile(join(ROOT, options.render), 'utf8'));
    await mkdir(join(ROOT, options.outDir), { recursive: true });
    await writeFile(join(ROOT, options.outDir, 'test-scenarios.md'), renderMarkdown(catalog));
    log(`re-rendered ${join(options.outDir, 'test-scenarios.md')} from ${options.render}`);
    return;
  }
  const startedAt = new Date();
  const branch = git('rev-parse', '--abbrev-ref', 'HEAD');
  const commit = git('rev-parse', '--short', 'HEAD');
  const dirty = git('status', '--porcelain').length > 0;
  const meta = {
    generatedAt: startedAt.toISOString(),
    repo: { branch, commit, dirty },
    host: { platform: `${process.platform} ${process.arch}`, node: process.version },
    mode: options.static ? 'static' : 'run',
  };

  const suites = [];
  const runs = {};

  // 1. Node main suite: test/*.test.mjs
  const mainFiles = await listFiles('test', name => name.endsWith('.test.mjs'));
  const agentFiles = await listFiles('agent/test', name => name.endsWith('.test.mjs'));

  if (!options.static) {
    log(`running ${mainFiles.length} Node suite files (concurrency ${options.concurrency})…`);
    const started = performance.now();
    const main = await scanNodeSuite(mainFiles, { timeoutFor: file => (file.includes('coordination') ? Math.max(options.timeoutMs, 1800000) : Math.max(options.timeoutMs, 900000)) });
    runs.main = { wallMs: round(performance.now() - started), files: main.files, timedOut: main.timedOut, errors: main.errors, retried: main.retried };
    suites.push(makeNodeSuite({
      id: 'node-main', name: 'Node 协议/单元套件', files: mainFiles,
      results: main.results, description: '`npm test` 跑的套件：协议桥、设备/模拟器适配、批处理、观察、安装流程、协调与租约。设备程序以隔离夹具替身，不碰真机与模拟器 UI。',
      tags: MAIN_FILE_TAGS, durationMs: runs.main.wallMs,
    }));

    log(`running ${agentFiles.length} agent suite files…`);
    const startedAgent = performance.now();
    const agent = await scanNodeSuite(agentFiles, { timeoutFor: () => options.timeoutMs });
    runs.agent = { wallMs: round(performance.now() - startedAgent), files: agent.files, timedOut: agent.timedOut, errors: agent.errors, retried: agent.retried };
    suites.push(makeNodeSuite({
      id: 'agent', name: 'Agent 套件', files: agentFiles,
      results: agent.results, description: '`agent/test` 的套件：任务运行器、开屏/回执/错误路由、imessage 与 telegram 渠道、超时与步骤处理。',
      tags: AGENT_FILE_TAGS, durationMs: runs.agent.wallMs,
    }));
  } else {
    suites.push(makeNodeSuite({ id: 'node-main', name: 'Node 协议/单元套件', files: mainFiles, results: staticResults(mainFiles), description: '未执行（--static）。', tags: MAIN_FILE_TAGS, durationMs: 0 }));
    suites.push(makeNodeSuite({ id: 'agent', name: 'Agent 套件', files: agentFiles, results: staticResults(agentFiles), description: '未执行（--static）。', tags: AGENT_FILE_TAGS, durationMs: 0 }));
  }

  // 2. action-efficiency scenarios (development + holdout, then the variant)
  if (options.static || !options.eval) {
    suites.push(staticEvalSuite('未执行（--static / --no-eval）。'));
    suites.push(staticEvalVariantSuite('未执行（--static / --no-eval）。'));
  } else {
    suites.push(await runEvalSuite(runs));
    suites.push(await runEvalVariantSuite(runs));
  }

  // 3. Poki Gym (iOS simulator only)
  suites.push(await scanGymSuite());

  // 4. Swift tests (needs Xcode + simulator)
  suites.push(await scanSwiftSuite());

  // 5. Rust tests (run with --rust)
  suites.push(options.rust && !options.static ? await runRustSuite(runs) : await scanRustSuite());

  // 6. manual phone checklist + playbooks
  suites.push(await scanChecklistSuite());
  suites.push(await scanPlaybookSuite());

  // 7. acceptance scripts
  suites.push(await scanAcceptanceSuite());

  // tool coverage
  const toolCoverage = await computeToolCoverage([
    ...mainFiles, ...agentFiles,
    ...(await listFiles('bin', name => name.startsWith('verify-') && name.endsWith('.mjs'))),
    'bin/eval-first-call.mjs',
    'test/suite/action-efficiency.test.mjs',
  ]);

  const catalog = {
    schemaVersion: 1,
    ...meta,
    runs,
    toolCoverage,
    totals: totalsOf(suites),
    capabilities: capabilityMatrix(suites),
    generalization: generalizationOf(suites, toolCoverage),
    suites,
    gaps: gapsOf(suites, runs),
  };

  await writeCatalog(catalog);
  log(`wrote ${join(options.outDir, 'test-scenarios.md')} and ${options.outDir}/test-scenarios.json`);
  console.log(summaryText(catalog));
}

function log(...args) { if (!options.quiet) console.log(...args); }

async function listFiles(dir, filter = () => true) {
  const entries = await readdir(join(ROOT, dir), { withFileTypes: true }).catch(() => []);
  return entries.filter(entry => entry.isFile() && filter(entry.name)).map(entry => join(dir, entry.name)).sort();
}

async function scanNodeSuite(files, { timeoutFor }) {
  const results = new Map();
  const retried = [];
  let index = 0;
  const worker = async () => {
    while (index < files.length) {
      const file = files[index++];
      const result = await scanTestFile(file, timeoutFor(file));
      results.set(file, result);
      log(`  ${result.status === 'ok' ? '·' : '!'} ${file} — ${result.tests.length} scenarios${result.status !== 'ok' ? ` (${result.status}${result.error ? `: ${result.error}` : ''})` : ''}`);
    }
  };
  await Promise.all(Array.from({ length: Math.min(options.concurrency, files.length) }, worker));

  // A failure under parallel load can be a machine artifact rather than a broken test. Retry once,
  // sequentially, before calling it a failure; a pass on retry keeps the scenarios and marks them
  // flaky so the catalog never hides load sensitivity.
  for (const file of files) {
    const first = results.get(file);
    // Retry only a file that ran but had failures: a timeout is a hang, not load sensitivity.
    if (!first || first.status !== 'ok' || !first.tests.some(test => test.status === 'fail')) continue;
    const retry = await scanTestFile(file, timeoutFor(file));
    retried.push(file);
    if (retry.status === 'ok' && !retry.tests.some(test => test.status === 'fail')) {
      retry.flaky = true;
      retry.firstPass = first;
      results.set(file, retry);
      log(`  ~ ${file} — passed on retry (first pass: ${first.status === 'timeout' ? 'timeout' : `${first.tests.filter(test => test.status === 'fail').length} failed`})`);
    } else {
      retry.firstPass = first;
      results.set(file, retry);
    }
  }
  const timedOut = [...results].filter(([, result]) => result.status === 'timeout').map(([file]) => file);
  const errors = [...results].filter(([, result]) => result.status === 'error').map(([file, result]) => `${file}: ${result.error}`);
  return { results, files: files.length, timedOut, errors, retried };
}

function scanTestFile(file, timeoutMs) {
  return new Promise(resolvePromise => {
    const child = spawn(process.execPath, ['--test', resolve(ROOT, file)], { cwd: ROOT, env: process.env, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    let settled = false;
    const settle = value => { if (!settled) { settled = true; resolvePromise(value); } };
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      settle({ status: 'timeout', tests: [], error: `no result after ${Math.round(timeoutMs / 1000)} s` });
    }, timeoutMs);
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('close', code => {
      clearTimeout(timer);
      const tests = parseSpecOutput(stdout);
      if (tests.length) settle({ status: 'ok', tests });
      else settle({ status: 'error', tests: [], error: `exit ${code}: ${oneLine(stderr || stdout).slice(-200)}` });
    });
    child.on('error', error => settle({ status: 'error', tests: [], error: error.message }));
  });
}

// Parses the spec reporter's flat output back into tests. The indentation says the nesting level
// (two spaces per level); a "✖" line's following indented lines carry the assertion message.
function parseSpecOutput(text) {
  const tests = [];
  const stack = [];
  let pending = null;
  for (const line of text.replace(/\x1b\[[0-9;]*m/g, '').split('\n')) {
    // The spec reporter repeats every failure once more under "failing tests:" after the counts;
    // stop there so a failure is never counted twice.
    if (/^ℹ\s+tests\s+\d+/.test(line)) break;
    const match = line.match(/^(\s*)([✔✖])\s+(.+)$/);
    if (!match) {
      if (pending && /^\s+\S/.test(line) && !/^\s*[✔✖▶ℹ]/.test(line)) {
        pending.detail = `${pending.detail ?? ''} ${line.trim()}`.slice(0, 200).trim();
        continue;
      }
      if (pending && line.trim() === '') pending = null;
      continue;
    }
    const indent = Math.floor(match[1].length / 2);
    let rest = match[3];
    const duration = rest.match(/\s+\(([\d.]+)\s*ms\)$/);
    let durationMs = 0;
    if (duration) { durationMs = Number(duration[1]); rest = rest.slice(0, duration.index); }
    stack[indent] = rest.trim();
    stack.length = indent + 1;
    const test = { name: stack.filter(Boolean).join(' > '), status: match[2] === '✔' ? 'pass' : 'fail', durationMs: round(durationMs) };
    if (test.status === 'fail') pending = test;
    else pending = null;
    tests.push(test);
  }
  return tests;
}

function staticResults(files) {
  const results = new Map();
  for (const file of files) results.set(file, { status: 'static', tests: [] });
  return results;
}

function makeNodeSuite({ id, name, files, results, description, tags, durationMs }) {
  const scenarios = [];
  let timedOutFiles = 0;
  for (const file of files) {
    const result = results.get(file) ?? { status: 'static', tests: [] };
    if (result.status === 'timeout') timedOutFiles++;
    const fileTags = tags[file] ?? ['session'];
    const flakyNames = new Set(result.flaky ? (result.firstPass?.tests ?? []).filter(test => test.status === 'fail').map(test => test.name) : []);
    for (const test of result.tests) {
      const flaky = flakyNames.has(test.name);
      scenarios.push({
        name: test.name,
        file,
        status: test.status,
        durationMs: test.durationMs ?? 0,
        capabilities: extraTags(test.name, fileTags),
        detail: test.detail ?? test.error ?? (flaky ? '并行首跑失败，串行重跑通过（记为 flaky）' : undefined),
        flaky: flaky || undefined,
        automation: 'auto',
        origin: 'node:test',
        split: 'regression',
      });
    }
    if (result.status !== 'ok') {
      const placeholder = result.status === 'static'
        ? { name: '（整个文件：执行后枚举每条场景）', status: 'not-run', detail: '静态盘点（--static）' }
        : result.status === 'timeout'
          ? { name: '（整个文件超时，未返回场景结果）', status: 'timeout', detail: result.error }
          : { name: `（文件未能执行：${oneLine(result.error) || result.status}）`, status: 'error', detail: result.error };
      scenarios.push({
        name: placeholder.name,
        file,
        status: placeholder.status,
        durationMs: 0,
        capabilities: fileTags,
        detail: placeholder.detail,
        automation: 'auto',
        origin: 'node:test',
        split: 'regression',
      });
    }
  }
  const retriedFiles = [...results.values()].filter(result => result.firstPass).length;
  const suite = { id, name, kind: 'file', entry: id === 'node-main' ? 'npm test' : 'cd agent && npm test', automation: 'auto', description, scenarios, files: files.length, timedOutFiles, retriedFiles, durationMs };
  suite.metrics = suiteMetrics(suite);
  return suite;
}

function extraTags(testName, base) {
  const text = words(testName);
  const tags = new Set(base);
  if (/(approv|payment|consent|input lock|blocked)/.test(text)) tags.add('safety');
  if (/(efficien|latency|memory|cpu|resource|sampling|perf)/.test(text)) tags.add('efficiency');
  if (/(soak|recover|restart|cancel|timeout|expire|crash|retry|stale|fault|hang)/.test(text)) tags.add('stability');
  if (/(diagnostic|record|replay|log|evidence|capture)/.test(text)) tags.add('diagnostics');
  return uniq([...tags]);
}

// ---------------------------------------------------------------------------------------------
// action-efficiency scenarios
// ---------------------------------------------------------------------------------------------

function staticEvalSuite(reason) {
  return staticEvalList({ id: 'eval', name: '动作效率对照场景', names: Object.keys(EVAL_META), splitOf: meta => meta.group === 'holdout' ? 'holdout' : 'development', description: '同一合成夹具上成对比较：引用直达与条件等待开/关（before/after），独立验收动作记录与最终屏幕。6 个场景 × 2 组。', reason });
}

function staticEvalVariantSuite(reason) {
  return staticEvalList({ id: 'eval-variant', name: '动作效率场景·变体（扰动）', names: ['interruption', 'canvas'], splitOf: () => 'variant', description: '把遮挡场景的角色、按钮与出现时序，以及 Canvas 场景的目标与 AX 干扰项换掉后的同一批场景，用来检验系统是否只记住了原场景的表面特征。', reason });
}

function staticEvalList({ id, name, names, splitOf, description, reason }) {
  const scenarios = names.map(scenarioName => {
    const meta = EVAL_META[scenarioName];
    return {
      name: `${scenarioName}（${meta.zh}）`, file: 'test/suite/action-efficiency.test.mjs', line: 0,
      status: 'not-run', durationMs: 0, capabilities: EVAL_TAGS[scenarioName] ?? ['efficiency'],
      automation: 'auto', origin: 'scenario', group: meta.group, split: splitOf(meta), detail: reason,
    };
  });
  const suite = { id, name, kind: 'scenario', entry: evalEntry(id), automation: 'auto', description, scenarios, files: 1, durationMs: 0 };
  suite.metrics = suiteMetrics(suite);
  return suite;
}

function evalEntry(id) {
  return id === 'eval-variant'
    ? 'POKI_EVAL_SCENARIO=interruption,canvas POKI_EVAL_VARIANT=1 node --test test/suite/action-efficiency.test.mjs'
    : 'POKI_EVAL_GROUP=all node --test test/suite/action-efficiency.test.mjs';
}

async function runEvalSuite(runs) {
  return runEvalSuiteWith({
    id: 'eval', name: '动作效率对照场景', names: Object.keys(EVAL_META), splitOf: meta => meta.group === 'holdout' ? 'holdout' : 'development',
    env: { POKI_EVAL_GROUP: 'all' }, runsKey: 'eval', runs,
    description: '同一合成夹具上成对比较：引用直达与条件等待开/关（before/after），独立验收动作记录与最终屏幕。6 个场景 × 2 组。',
  });
}

async function runEvalVariantSuite(runs) {
  return runEvalSuiteWith({
    id: 'eval-variant', name: '动作效率场景·变体（扰动）', names: ['interruption', 'canvas'], splitOf: () => 'variant',
    env: { POKI_EVAL_GROUP: 'all', POKI_EVAL_SCENARIO: 'interruption,canvas', POKI_EVAL_VARIANT: '1' }, runsKey: 'evalVariant', runs,
    description: '把遮挡场景的角色、按钮与出现时序，以及 Canvas 场景的目标与 AX 干扰项换掉后的同一批场景，用来检验系统是否只记住了原场景的表面特征。',
  });
}

async function runEvalSuiteWith({ id, name, names, splitOf, env, runsKey, runs, description }) {
  const resultsFile = join(tmpdir(), `poki-eval-${id}-${process.pid}-${Date.now()}.jsonl`);
  const started = performance.now();
  const outcome = await spawnCollect(process.execPath, ['--test', 'test/suite/action-efficiency.test.mjs'], {
    cwd: ROOT, timeoutMs: 600000, env: { ...process.env, POKI_EVAL_RESULTS: resultsFile, ...env },
  });
  const wallMs = round(performance.now() - started);
  let rows = [];
  try {
    rows = (await readFile(resultsFile, 'utf8')).trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
  } catch { /* no result file: the suite failed before running */ }
  const byName = new Map();
  for (const row of rows) {
    if (!byName.has(row.name)) byName.set(row.name, []);
    byName.get(row.name).push(row);
  }
  const scenarios = [];
  for (const scenarioName of names) {
    const meta = EVAL_META[scenarioName];
    const pair = byName.get(scenarioName) ?? [];
    if (!pair.length) {
      scenarios.push({
        name: `${scenarioName}（${meta.zh}）`, file: 'test/suite/action-efficiency.test.mjs', status: 'not-run', durationMs: 0,
        capabilities: EVAL_TAGS[scenarioName] ?? ['efficiency'], automation: 'auto', origin: 'scenario', group: meta.group, split: splitOf(meta),
        detail: `${outcome.status}：${oneLine(outcome.stderr || outcome.stdout).slice(-160)}`,
      });
      continue;
    }
    const before = pair.find(row => !row.after) ?? {};
    const after = pair.find(row => row.after) ?? {};
    const failed = pair.filter(row => row.passed === false);
    scenarios.push({
      name: `${scenarioName}（${meta.zh}）`, file: 'test/suite/action-efficiency.test.mjs', status: failed.length ? 'fail' : 'pass',
      durationMs: round(pair.reduce((total, row) => total + (row.elapsed_ms ?? 0), 0)),
      capabilities: EVAL_TAGS[scenarioName] ?? ['efficiency'], automation: 'auto', origin: 'scenario', group: meta.group, split: splitOf(meta),
      detail: `before ${before.elapsed_ms ?? '—'} ms / ${before.tool_calls ?? '—'} calls；after ${after.elapsed_ms ?? '—'} ms / ${after.tool_calls ?? '—'} calls`,
      metrics: { before: pickRow(before), after: pickRow(after) },
    });
  }
  runs[runsKey] = { wallMs, rows: rows.length, status: outcome.status, failures: scenarios.filter(scenario => scenario.status === 'fail').length };
  const suite = { id, name, kind: 'scenario', entry: evalEntry(id), automation: 'auto', description, scenarios, files: 1, durationMs: wallMs };
  suite.metrics = suiteMetrics(suite);
  return suite;
}

function pickRow(row) {
  if (!row || row.elapsed_ms == null) return null;
  return { elapsedMs: round(row.elapsed_ms), toolCalls: row.tool_calls ?? null, directHits: row.direct_hits ?? null, passed: row.passed ?? null };
}

// ---------------------------------------------------------------------------------------------
// Poki Gym (simulator)
// ---------------------------------------------------------------------------------------------

async function scanGymSuite() {
  const appFile = 'native/ios-gym/Gym/GymApp.swift';
  const scorecardFile = 'native/ios-gym/check/GymScorecard.swift';
  const app = await readText(appFile);
  const scorecard = await readText(scorecardFile);
  const scenarios = [];

  // The MCP tool catalog's simulator target: one screen per hard case.
  const enumLine = lineOf(app, /^\s*case\s+animation,/) ?? 0;
  const caseNames = (app.match(/case\s+animation,\s*alert,\s*paste,\s*list,\s*sheet,\s*focus,\s*dense,\s*dup,\s*fullscreen,\s*nav,\s*interrupt,\s*approval/) ?? [''])[0]
    .replace('case ', '').split(',').map(item => item.trim());
  const blurbs = new Map();
  for (const match of app.matchAll(/case \.(\w+): "([^"]*)"/g)) blurbs.set(match[1], match[2]);
  for (const name of caseNames) {
    scenarios.push({
      name: `gym:${name} — ${blurbs.get(name) ?? ''}`.trim(),
      file: appFile, line: enumLine, status: 'not-run', durationMs: 0,
      capabilities: GYM_TAGS[name] ?? ['observe'], automation: 'simulator', origin: 'scenario', split: 'unseen', detail: '需 Xcode 构建 Poki Gym 并在模拟器上运行 scorecard',
    });
  }

  // The scorecard: every numbered block it drives, plus the faults it injects.
  const scorecardLines = scorecard.split('\n');
  for (let index = 0; index < scorecardLines.length; index++) {
    const match = scorecardLines[index].match(/^\s*\/\/ (\d+)\. (.*)$/);
    if (!match) continue;
    let text = match[2].trim();
    for (let next = index + 1; next < scorecardLines.length; next++) {
      const continuation = scorecardLines[next].match(/^\s*\/\/ ?(.*)$/);
      if (!continuation || /^\s*\/\/ \d+\./.test(scorecardLines[next]) || !continuation[1].trim()) break;
      text += ` ${continuation[1].trim()}`;
    }
    const line = index + 1;
    scenarios.push({
      name: `scorecard ${match[1]}. ${text}`,
      file: scorecardFile, line, status: 'not-run', durationMs: 0,
      capabilities: scorecardTags(match[2]), automation: 'simulator', origin: 'scenario', split: 'unseen',
      detail: '需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径）',
    });
  }
  const seenFaults = new Set();
  for (const match of scorecard.matchAll(/^\s*scenario = "([^"]+)"/gm)) {
    if (seenFaults.has(match[1])) continue;
    seenFaults.add(match[1]);
    const line = lineOf(scorecard, new RegExp(`^\\s*scenario = "${escapeRegExp(match[1])}"`)) ?? 0;
    scenarios.push({
      name: `scorecard 故障注入：${match[1]}`, file: scorecardFile, line, status: 'not-run', durationMs: 0,
      capabilities: ['stability'], automation: 'simulator', origin: 'fault', split: 'unseen', detail: '需模拟器；faults 只在 runner 路径运行',
    });
  }
  const suite = {
    id: 'gym', name: 'Poki Gym 模拟器场景', kind: 'simulator', entry: '.github/workflows/ios-gym.yml（scorecard / scorecard-inprocess）',
    automation: 'simulator', description: '一个模拟器 App，每个场景屏对应一种会卡住 UI 自动化的真实情况；scorecard 逐屏驱动 look/do、系统 App 与故障注入。本机未运行（需 Xcode 与模拟器）。',
    scenarios, files: 2, durationMs: 0,
  };
  suite.metrics = suiteMetrics(suite);
  return suite;
}

function scorecardTags(text) {
  const value = text.toLowerCase();
  if (value.includes('payment') || value.includes('approval')) return ['safety', 'act'];
  if (value.includes('animation') || value.includes('dense') || value.includes('tree')) return ['observe', 'act'];
  if (value.includes('alert') || value.includes('type') || value.includes('list') || value.includes('sheet') || value.includes('focus') || value.includes('decoy') || value.includes('web view') || value.includes('navigation') || value.includes('safari') || value.includes('photos') || value.includes('settings') || value.includes('finish')) return ['act', 'observe'];
  if (value.includes('relaunch') || value.includes('fault')) return ['stability'];
  return ['act'];
}

// ---------------------------------------------------------------------------------------------
// Swift tests (static: needs Xcode + simulator)
// ---------------------------------------------------------------------------------------------

async function scanSwiftSuite() {
  const dirs = ['native/ios/PokiCore/Tests/PokiCoreTests', 'native/ios/PokiLoopback/Tests/PokiLoopbackTests', 'native/ios-app/PokiTests'];
  const files = [];
  for (const dir of dirs) for (const file of await listFiles(dir, name => name.endsWith('.swift'))) files.push(file);
  const scenarios = [];
  for (const file of files) {
    const source = await readText(file);
    for (const match of source.matchAll(/func (test\w+)\s*\(/g)) {
      const line = source.slice(0, match.index).split('\n').length;
      scenarios.push({
        name: match[1], file, line, status: 'not-run', durationMs: 0,
        capabilities: extraTags(match[1], SWIFT_FILE_TAGS[file] ?? ['session']),
        automation: 'simulator', origin: 'xctest', split: 'regression',
        detail: '需 Xcode + iOS 模拟器（xcodebuild test）',
      });
    }
  }
  const suite = {
    id: 'swift', name: 'Swift 测试（PokiCore / Poki 应用）', kind: 'xctest', entry: 'xcodebuild test（PokiCoreTests / PokiTests）',
    automation: 'simulator', description: 'PokiCore 的 XCTest（复连、故障、look/do、soak、例行流程）与 Poki 应用的 XCTest（会话、剪贴板、语音、交接）。静态盘点，本机未运行。',
    scenarios, files: files.length, durationMs: 0,
  };
  suite.metrics = suiteMetrics(suite);
  return suite;
}

// ---------------------------------------------------------------------------------------------
// Rust tests (desktop workspace and the two native crates)
// ---------------------------------------------------------------------------------------------

const RUST_CRATES = [
  { id: 'desktop', root: 'desktop', manifest: 'desktop/Cargo.toml', label: 'desktop 工作区（Setup）', args: ['--workspace'] },
  { id: 'bridge', root: 'native/bridge', manifest: 'native/bridge/Cargo.toml', label: 'native/bridge（真机桥）', args: [] },
  { id: 'launcher', root: 'native/launcher', manifest: 'native/launcher/Cargo.toml', label: 'native/launcher（Launcher）', args: [] },
];

async function scanRustSuite() {
  return rustSuiteFromSource({ status: 'not-run', reason: '未运行（加 --rust 运行；需要可写的 CARGO_HOME 与一次构建）' });
}

async function runRustSuite(runs) {
  const suite = await rustSuiteFromSource();
  const executed = new Map();
  let wallMs = 0;
  for (const crate of RUST_CRATES) {
    const started = performance.now();
    const outcome = await spawnCollect('cargo', ['test', '--manifest-path', crate.manifest, ...crate.args, '--no-fail-fast'], { cwd: ROOT, timeoutMs: 1800000 });
    const elapsed = round(performance.now() - started);
    wallMs += elapsed;
    const { tests, panics } = parseCargoTests(`${outcome.stdout}\n${outcome.stderr}`);
    runs[`rust-${crate.id}`] = { wallMs: elapsed, status: outcome.status, executed: tests.length };
    if (tests.length) executed.set(crate.id, tests.map(test => ({ ...test, panic: panics.get(test.name) ?? [...panics].find(([name]) => name.endsWith(test.name.split('::').pop()))?.[1] })));
    else {
      suite.scenarios.push({
        name: `（${crate.label} 构建/测试未产出结果）`, file: crate.manifest, line: 0, status: 'error', durationMs: 0,
        capabilities: ['install'], automation: 'auto', origin: 'rust', split: 'regression', crate: crate.id,
        detail: oneLine(outcome.stderr || outcome.stdout).slice(-200),
      });
    }
  }
  for (const [crateId, tests] of executed) {
    const byBare = new Map();
    for (const test of tests) {
      const bare = test.name.split('::').pop();
      if (!byBare.has(bare)) byBare.set(bare, []);
      byBare.get(bare).push(test);
    }
    for (const scenario of suite.scenarios) {
      if (scenario.crate !== crateId || scenario.status !== 'not-run') continue;
      const candidates = byBare.get(scenario.name);
      if (!candidates?.length) continue;
      const test = candidates.shift();
      scenario.status = test.status;
      scenario.name = test.name;
      scenario.detail = test.panic ? oneLine(test.panic).slice(0, 200) : undefined;
      if (test.status === 'fail' && /AddrNotAvailable|EADDRNOTAVAIL|Can't assign requested address/.test(test.panic ?? '')) {
        scenario.status = 'not-run';
        scenario.detail = '环境阻断：本机无法绑定测试用的网络地址（EADDRNOTAVAIL），需在未沙箱化的机器上运行';
      }
    }
    for (const candidates of byBare.values()) {
      for (const test of candidates) {
        const crate = RUST_CRATES.find(item => item.id === crateId);
        const sandboxed = test.status === 'fail' && /AddrNotAvailable|EADDRNOTAVAIL|Can't assign requested address/.test(test.panic ?? '');
        suite.scenarios.push({
          name: test.name, file: `${crate.root}/src`, line: 0, status: sandboxed ? 'not-run' : test.status, durationMs: 0,
          capabilities: rustTags(crateId, test.name), automation: 'auto', origin: 'rust', split: 'regression', crate: crateId,
          detail: sandboxed ? '环境阻断：本机无法绑定测试用的网络地址（EADDRNOTAVAIL），需在未沙箱化的机器上运行' : (test.panic ? oneLine(test.panic).slice(0, 200) : '执行后枚举（源码盘点没有对应的 #[test] 行）'),
        });
      }
    }
  }
  for (const scenario of suite.scenarios) {
    if (scenario.status === 'not-run') scenario.detail ??= '本次 cargo test 未包含（平台/feature 过滤、非默认成员或构建跳过）';
  }
  suite.durationMs = wallMs;
  suite.metrics = suiteMetrics(suite);
  runs.rust = { wallMs, crates: Object.fromEntries(RUST_CRATES.map(crate => [crate.id, runs[`rust-${crate.id}`]?.executed ?? 0])) };
  return suite;
}

function parseCargoTests(output) {
  const tests = [];
  const panics = new Map();
  let module = '';
  let panicking = null;
  for (const line of output.split('\n')) {
    const running = line.match(/^\s*Running (?:unittests )?(\S+)/);
    if (running) module = running[1].replace(/^.*?\/deps\//, '').replace(/-\w+$/, '').replace(/\//g, ' ') || running[1];
    const test = line.match(/^test ([\w:]+) \.\.\. (ok|FAILED|ignored)$/);
    if (test) { tests.push({ name: test[1], status: test[2] === 'ok' ? 'pass' : test[2] === 'ignored' ? 'skipped' : 'fail', module }); continue; }
    const panic = line.match(/^thread '([^']+)' .*panicked at/);
    if (panic) { panicking = panic[1]; panics.set(panicking, ''); continue; }
    if (panicking && line.trim()) { panics.set(panicking, `${panics.get(panicking) ?? ''} ${line.trim()}`.trim()); panicking = null; }
  }
  return { tests, panics };
}

async function rustSuiteFromSource(state = { status: 'not-run', reason: '未运行' }) {
  const scenarios = [];
  for (const crate of RUST_CRATES) {
    for (const file of await walk(crate.root, name => name.endsWith('.rs'))) {
      const source = await readText(file);
      for (const match of source.matchAll(/#\[(?:tokio::)?test\]/g)) {
        const tail = source.slice(match.index, match.index + 400);
        const fn = tail.match(/fn ([\w]+)\s*\(/);
        if (!fn) continue;
        const line = source.slice(0, match.index).split('\n').length;
        scenarios.push({
          name: fn[1], file, line, status: state.status === 'error' ? 'error' : 'not-run', durationMs: 0,
          capabilities: rustTags(crate.id, fn[1]), automation: 'auto', origin: 'rust', split: 'regression', crate: crate.id,
          detail: state.reason,
        });
      }
    }
  }
  const suite = {
    id: 'rust', name: 'Rust 测试（desktop / native）', kind: 'rust',
    entry: 'cargo test（desktop 工作区、native/bridge、native/launcher）',
    automation: 'auto', description: 'Poki 的 Rust 代码：Setup 工作区（USB/Wi-Fi、Apple 账号、签名）、真机桥、Launcher、soak 与远程会话。', scenarios,
    files: new Set(scenarios.map(scenario => scenario.file)).size, durationMs: 0,
  };
  suite.metrics = suiteMetrics(suite);
  return suite;
}

function moduleKeyOf(fileOrModule = '') {
  const text = String(fileOrModule).toLowerCase();
  for (const key of ['launcher', 'bridge', 'mac', 'cli', 'app', 'core']) if (text.includes(key)) return key;
  return 'core';
}

function rustTags(module, name) {
  const tags = new Set(RUST_MODULE_TAGS[module] ?? ['install']);
  if (/(soak|timeout|cancel|recover|retry|fail|error)/.test(words(name))) tags.add('stability');
  if (/(approv|payment|consent|danger)/.test(words(name))) tags.add('safety');
  return [...tags];
}

// ---------------------------------------------------------------------------------------------
// manual phone checklist and verification playbooks
// ---------------------------------------------------------------------------------------------

async function scanChecklistSuite() {
  const file = 'docs/device-test-checklist.md';
  const source = await readText(file);
  const scenarios = [];
  const lines = source.split('\n');
  let section = '0. Before';
  let current = null;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const heading = line.match(/^## (.+)$/);
    if (heading) { section = heading[1].trim(); current = null; continue; }
    const item = line.match(/^- \[ \] (.+)$/);
    if (item) {
      current = { text: item[1], line: i + 1 };
      const sectionKey = Object.keys(CHECKLIST_TAGS).find(key => section.startsWith(key)) ?? '';
      scenarios.push({
        name: item[1], file, line: i + 1, status: 'not-run', durationMs: 0,
        capabilities: CHECKLIST_TAGS[sectionKey] ?? ['install'], automation: 'device', origin: 'manual', split: 'device', section,
        detail: '人工真机检查项',
      });
      continue;
    }
    if (current && /^\s{2,}\S/.test(line) && !line.match(/^\s*$/)) {
      const last = scenarios[scenarios.length - 1];
      last.name += ` ${line.trim()}`;
      current.text += ` ${line.trim()}`;
    } else if (line.trim() === '') {
      current = null;
    }
  }
  const suite = {
    id: 'checklist', name: '真机人工检查清单', kind: 'manual', entry: 'docs/device-test-checklist.md',
    automation: 'device', description: '必须在真机上按顺序执行的检查项：回环、配对、Launcher、中继、审批、Live Activity。', scenarios, files: 1, durationMs: 0,
  };
  suite.metrics = suiteMetrics(suite);
  return suite;
}

async function scanPlaybookSuite() {
  const files = ['docs/verification/cellular-test-plan.md', 'docs/verification/lan-bonjour-recovery.md', 'docs/verification/tailscale-pr-validation.md', 'docs/native-ime-testing.md'];
  const scenarios = [];
  for (const file of files) {
    if (!existsSync(join(ROOT, file))) continue;
    const source = await readText(file);
    const sections = [...source.matchAll(/^## (.+)$/gm)].map(match => match[1].trim());
    const label = file.replace(/^docs\//, '').replace(/\.md$/, '');
    scenarios.push({
      name: `${label}（${sections.length} 个验证段：${sections.slice(0, 3).join(' / ')}${sections.length > 3 ? ' …' : ''}）`,
      file, line: 1, status: 'not-run', durationMs: 0,
      capabilities: PLAYBOOK_TAGS[file] ?? ['session'], automation: 'device', origin: 'playbook', split: 'device', detail: '人工验证预案，按文档步骤在真机/真网环境执行',
    });
  }
  const suite = {
    id: 'playbook', name: '人工验证预案', kind: 'manual', entry: 'docs/verification/*.md、docs/native-ime-testing.md',
    automation: 'device', description: '针对真机、真实网络与 IME 的验证预案；不进入自动套件。', scenarios, files: files.length, durationMs: 0,
  };
  suite.metrics = suiteMetrics(suite);
  return suite;
}

// ---------------------------------------------------------------------------------------------
// acceptance scripts on a real simulator/phone
// ---------------------------------------------------------------------------------------------

async function scanAcceptanceSuite() {
  const files = (await listFiles('bin', name => name.startsWith('verify-') && name.endsWith('.mjs'))).concat('bin/eval-first-call.mjs');
  const scenarios = [];
  for (const file of files) {
    if (!existsSync(join(ROOT, file))) continue;
    const source = await readText(file);
    const description = file.endsWith('eval-first-call.mjs')
      ? '度量全新的 Claude Code / Codex CLI 窗口在一次性模拟器上完成同一任务的往返次数与耗时（无断言，输出对照报告）'
      : oneLine(source.split('\n').filter(line => line.trim().startsWith('//')).slice(0, 4).map(line => line.replace(/^\s*\/\/\s?/, '')).join(' ')).slice(0, 220);
    const asserts = (source.match(/assert\./g) ?? []).length;
    const needs = /udid|simctl|booted/i.test(source) ? 'simulator' : 'device';
    scenarios.push({
      name: `${file}${asserts ? `（${asserts} 处断言）` : '（度量脚本）'}${description ? ` — ${description}` : ''}`.trim(),
      file, line: 1, status: 'not-run', durationMs: 0,
      capabilities: /eval-first-call/.test(file) ? ['efficiency', 'agent'] : needs === 'simulator' ? ['act', 'observe'] : ['act', 'observe', 'safety'],
      automation: needs === 'simulator' ? 'simulator' : 'device', origin: 'script', split: 'acceptance',
      detail: '验收脚本：需要专用一次性模拟器或真机，手动运行',
    });
  }
  const suite = {
    id: 'acceptance', name: '模拟器/真机验收脚本', kind: 'acceptance', entry: 'bin/verify-*.mjs、bin/eval-first-call.mjs',
    automation: 'device', description: '对真实设备做 UI 与状态变更的验收脚本，故意不进入 npm test。', scenarios, files: files.length, durationMs: 0,
  };
  suite.metrics = suiteMetrics(suite);
  return suite;
}

// ---------------------------------------------------------------------------------------------
// tool coverage
// ---------------------------------------------------------------------------------------------

async function computeToolCoverage(testFiles) {
  const catalog = JSON.parse(await readText('src/data/tools.json'));
  const tools = (catalog.tools ?? []).map(tool => tool.name).filter(Boolean);
  const read = async file => (existsSync(join(ROOT, file)) ? readText(file) : '');
  const mentionFiles = uniq([
    ...testFiles,
    ...(await listFiles('docs/verification', name => name.endsWith('.md'))),
    'docs/device-test-checklist.md', 'docs/native-ime-testing.md',
  ]);
  // End-to-end surfaces: the scenario suites, the Gym scorecard, the manual device scripts and the
  // verification scripts. These drive tools for real, so they are the honest coverage number.
  const endToEndFiles = uniq([
    'native/ios-gym/check/GymScorecard.swift',
    'test/suite/action-efficiency.test.mjs',
    'docs/device-test-checklist.md',
    'docs/native-ime-testing.md',
    ...(await listFiles('docs/verification', name => name.endsWith('.md'))),
    ...(await listFiles('bin', name => name.startsWith('verify-') && name.endsWith('.mjs'))),
    'bin/eval-first-call.mjs',
  ]);
  const mentionText = (await Promise.all(mentionFiles.map(read))).join('\n');
  const endToEndText = (await Promise.all(endToEndFiles.map(read))).join('\n');
  const scan = text => {
    const covered = [];
    const uncovered = [];
    for (const tool of tools) {
      const pattern = new RegExp(`(?<![\\w])${escapeRegExp(tool)}(?![\\w])`);
      (pattern.test(text) ? covered : uncovered).push(tool);
    }
    return { covered: covered.length, uncovered, percent: tools.length ? round(covered.length / tools.length * 100) : 0 };
  };
  return { total: tools.length, mentions: scan(mentionText), exercised: scan(endToEndText) };
}

// ---------------------------------------------------------------------------------------------
// aggregates
// ---------------------------------------------------------------------------------------------

function capabilityMatrix(suites) {
  const rows = {};
  for (const key of Object.keys(CAPS)) {
    const row = { key, ...CAPS[key], total: 0, bySuite: {}, automated: 0, passed: 0, executed: 0 };
    for (const suite of suites) {
      const matching = suite.scenarios.filter(scenario => scenario.capabilities?.includes(key));
      if (matching.length) row.bySuite[suite.id] = matching.length;
      row.total += matching.length;
      row.automated += matching.filter(scenario => scenario.automation === 'auto').length;
      row.executed += matching.filter(scenario => ['pass', 'fail'].includes(scenario.status)).length;
      row.passed += matching.filter(scenario => scenario.status === 'pass').length;
    }
    rows[key] = row;
  }
  return rows;
}

function generalizationOf(suites, toolCoverage) {
  const all = suites.flatMap(suite => suite.scenarios);
  const order = ['regression', 'development', 'holdout', 'variant', 'unseen', 'device', 'acceptance'];
  const slices = order.map(key => {
    const matching = all.filter(scenario => scenario.split === key);
    const counts = statusCounts(matching);
    const executed = matching.filter(scenario => ['pass', 'fail'].includes(scenario.status));
    return {
      key, ...SPLITS[key], scenarios: matching.length, executed: executed.length,
      pass: counts.pass, fail: counts.fail, timeout: counts.timeout,
      notRun: counts['not-run'] + counts.error,
      passRate: executed.length ? round(counts.pass / executed.length * 100) : null,
    };
  });
  const slice = key => slices.find(item => item.key === key);
  const development = slice('development');
  const holdout = slice('holdout');
  const variant = slice('variant');
  const unseen = slice('unseen');
  const gap = development?.passRate != null && holdout?.passRate != null ? round(development.passRate - holdout.passRate) : null;
  const capabilities = Object.values(capabilityMatrix(suites));
  const coveredCapabilities = capabilities.filter(row => row.total > 0).length;
  const environments = uniq(all.map(scenario => scenario.automation)).length;
  const warnings = [];
  if (holdout?.executed) {
    if (gap != null && gap > 10) warnings.push(`留出集通过率 ${holdout.passRate}% 比开发集 ${development.passRate}% 低 ${gap} 个百分点：出现过拟合信号，先检查是不是只对开发集场景做了调优。`);
  } else {
    warnings.push('本轮没有运行留出集：无法判断是否过拟合。评估日请运行 `node bin/test-catalog.mjs`。');
  }
  if (variant?.executed) {
    const reference = holdout?.passRate ?? development?.passRate;
    if (variant.passRate != null && reference != null && variant.passRate < reference) warnings.push(`变体通过率 ${variant.passRate}% 低于原场景 ${reference}%：可能记住了角色、文案或出现时序等表面特征。`);
  } else {
    warnings.push('本轮没有运行变体场景（`POKI_EVAL_VARIANT=1`）：没有检验“换文案、换角色、换时序”后是否仍然通过。');
  }
  if (!unseen?.executed) warnings.push('未见场景（Poki Gym / 真机清单）本轮未运行：只能说明“回归没坏”，不能说明“泛化好”。');
  if ((toolCoverage?.exercised?.percent ?? 0) < 70) warnings.push(`端到端工具覆盖只有 ${toolCoverage?.exercised?.percent ?? 0}%：能力面仍有空白。`);
  return {
    slices, gap, warnings,
    diversity: {
      capabilities: coveredCapabilities, capabilityTotal: Object.keys(CAPS).length,
      tools: toolCoverage?.exercised?.percent ?? 0, environments, suites: suites.length,
      holdoutCapabilities: uniq(all.filter(scenario => scenario.split === 'holdout').flatMap(scenario => scenario.capabilities ?? [])),
      unseenCapabilities: uniq(all.filter(scenario => scenario.split === 'unseen').flatMap(scenario => scenario.capabilities ?? [])),
    },
  };
}

function totalsOf(suites) {
  const all = suites.flatMap(suite => suite.scenarios);
  const counts = statusCounts(all);
  const executed = all.filter(scenario => ['pass', 'fail'].includes(scenario.status));
  return {
    scenarios: all.length,
    executed: executed.length,
    ...counts,
    passRate: executed.length ? round(counts.pass / executed.length * 100) : null,
    automated: all.filter(scenario => scenario.automation === 'auto').length,
    needsSimulator: all.filter(scenario => scenario.automation === 'simulator').length,
    needsDevice: all.filter(scenario => scenario.automation === 'device').length,
    flaky: all.filter(scenario => scenario.flaky).length,
    durationMs: round(suites.reduce((total, suite) => total + (suite.durationMs ?? 0), 0)),
    slowest: all.filter(scenario => scenario.durationMs > 0).sort((a, b) => b.durationMs - a.durationMs).slice(0, 10)
      .map(scenario => ({ name: scenario.name, file: scenario.file, durationMs: scenario.durationMs, suite: scenario.file?.startsWith('agent/') ? 'agent' : 'node-main' })),
  };
}

function gapsOf(suites, runs) {
  const gaps = [];
  for (const suite of suites) {
    const timedOut = suite.scenarios.filter(scenario => scenario.status === 'timeout');
    for (const scenario of timedOut) gaps.push(`${suite.name} / ${scenario.file}：${scenario.name}`);
    const errored = suite.scenarios.filter(scenario => scenario.status === 'error');
    for (const scenario of errored.slice(0, 5)) gaps.push(`${suite.name} / ${scenario.file}：${scenario.name}${scenario.detail ? `（${scenario.detail}）` : ''}`);
  }
  const environmentBlocked = suites.flatMap(suite => suite.scenarios.filter(scenario => scenario.status === 'not-run' && /环境阻断/.test(scenario.detail ?? '')).map(scenario => `${suite.name} / ${scenario.file}：${scenario.name}（${scenario.detail}）`));
  for (const item of environmentBlocked) gaps.push(item);
  const failed = suites.flatMap(suite => suite.scenarios.filter(scenario => scenario.status === 'fail').map(scenario => `${suite.name} / ${scenario.file}：${scenario.name}${scenario.detail ? `（${scenario.detail.slice(0, 90)}）` : ''}`));
  for (const item of failed.slice(0, 20)) gaps.push(`失败：${item}`);
  const flaky = suites.flatMap(suite => suite.scenarios.filter(scenario => scenario.flaky).map(scenario => `${suite.name} / ${scenario.file}：${scenario.name}`));
  for (const item of flaky.slice(0, 10)) gaps.push(`不稳定（并行首跑失败、串行重跑通过）：${item}`);
  if (runs.main?.timedOut?.length) gaps.push(`主套件超时文件：${runs.main.timedOut.join('、')}`);
  if (runs.agent?.timedOut?.length) gaps.push(`Agent 套件超时文件：${runs.agent.timedOut.join('、')}（这些场景当前拿不到结果）`);
  return gaps;
}

// ---------------------------------------------------------------------------------------------
// output
// ---------------------------------------------------------------------------------------------

async function writeCatalog(catalog) {
  await mkdir(join(ROOT, options.outDir), { recursive: true });
  await writeFile(join(ROOT, options.outDir, 'test-scenarios.json'), JSON.stringify(catalog, null, 1) + '\n');
  await writeFile(join(ROOT, options.outDir, 'test-scenarios.md'), renderMarkdown(catalog));
  if (options.static) return; // inventory-only runs are not capability baselines
  const historyFile = join(ROOT, options.history);
  await mkdir(dirname(historyFile), { recursive: true });
  const record = {
    at: catalog.generatedAt, commit: catalog.repo.commit, dirty: catalog.repo.dirty,
    totals: { scenarios: catalog.totals.scenarios, executed: catalog.totals.executed, pass: catalog.totals.pass, fail: catalog.totals.fail, timeout: catalog.totals.timeout, passRate: catalog.totals.passRate },
    suites: Object.fromEntries(catalog.suites.map(suite => [suite.id, { scenarios: suite.metrics.scenarios, pass: suite.metrics.pass, fail: suite.metrics.fail, timeout: suite.metrics.timeout, wallMs: suite.durationMs }])),
    toolCoverage: catalog.toolCoverage.exercised.percent,
  };
  await appendFile(historyFile, JSON.stringify(record) + '\n');
}

function summaryText(catalog) {
  const t = catalog.totals;
  const lines = [`scenarios ${t.scenarios}（实跑 ${t.executed}，通过 ${t.pass}，失败 ${t.fail}，超时 ${t.timeout}，flaky ${t.flaky ?? 0}，未跑 ${t['not-run']}）`];
  for (const suite of catalog.suites) lines.push(`  ${pad(suite.name, 28)} ${String(suite.metrics.scenarios).padStart(4)} 场景  ${suite.metrics.pass} pass  ${suite.metrics.fail} fail  ${suite.metrics.timeout} timeout  ${(suite.durationMs / 1000).toFixed(1)} s`);
  const holdout = catalog.generalization.slices.find(item => item.key === 'holdout');
  lines.push(`generalization: holdout ${holdout?.passRate ?? '—'}% (${holdout?.executed ?? 0} run), tool coverage: mentions ${catalog.toolCoverage.mentions.percent}% / end-to-end ${catalog.toolCoverage.exercised.percent}%`);
  return lines.join('\n');
}

function renderMarkdown(catalog) {
  const out = [];
  const t = catalog.totals;
  const gen = catalog.generalization;
  let section = 1;
  out.push('# Poki 测试场景总表（能力评估基线）', '');
  out.push(`> 自动生成，请勿手改。生成时间：${catalog.generatedAt.replace('T', ' ').replace(/\.\d+Z$/, ' UTC')}；仓库：\`${catalog.repo.branch}\` @ \`${catalog.repo.commit}\`${catalog.repo.dirty ? '（有未提交改动）' : ''}；环境：${catalog.host.platform}、Node ${catalog.host.node}。`);
  out.push('>');
  out.push('> 重新生成：`node bin/test-catalog.mjs`（默认实跑 Node 主套件、Agent 套件、动作效率场景与变体）；`--static` 只盘点，`--rust` 加上 desktop Rust 工作区，`--no-eval` 跳过动作效率场景。机器可读版本：`docs/test-scenarios.json`；每次运行追加一条趋势记录到 `.runtime/test-catalog/history.jsonl`。', '');
  out.push(`## ${section++}. 总览`, '');
  out.push(`共 **${t.scenarios}** 个场景：**${t.automated}** 个本机可自动运行，**${t.needsSimulator}** 个需要 iOS 模拟器/Xcode，**${t.needsDevice}** 个需要真机或人工操作。`);
  out.push(`本次实跑 **${t.executed}** 个：通过 ${t.pass}，失败 ${t.fail}，超时 ${t.timeout}，其中 flaky ${t.flaky ?? 0}${t.executed ? `，通过率 ${pct(t.pass, t.pass + t.fail)}` : ''}；未运行 ${t['not-run']} 个（静态盘点或需要设备/账号）。`, '');
  out.push('| 套件 | 入口 | 场景 | 实跑 | 通过 | 失败 | 超时 | flaky | 未跑 | 自动化 | 墙钟耗时 | 说明 |');
  out.push('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | --- |');
  for (const suite of catalog.suites) {
    const m = suite.metrics;
    const flakyCount = suite.scenarios.filter(scenario => scenario.flaky).length;
    out.push(`| ${cell(suite.name)} | \`${cell(suite.entry)}\` | ${m.scenarios} | ${m.executed} | ${m.pass} | ${m.fail} | ${m.timeout} | ${flakyCount || '·'} | ${m['not-run'] + m.error} | ${AUTO[suite.automation] ?? suite.automation} | ${formatMs(suite.durationMs)} | ${cell(suite.description)} |`);
  }
  const sum = (key) => catalog.suites.reduce((total, suite) => total + (suite.metrics[key] ?? 0), 0);
  out.push(`| **合计** | | **${t.scenarios}** | **${sum('executed')}** | **${sum('pass')}** | **${sum('fail')}** | **${sum('timeout')}** | **${t.flaky || 0}** | **${sum('not-run') + sum('error')}** | | **${formatMs(t.durationMs)}** | |`, '');

  if (t.slowest.length) {
    out.push('### 本次最慢的 10 个场景', '');
    out.push('| 场景 | 文件 | 耗时 |');
    out.push('| --- | --- | ---: |');
    for (const item of t.slowest) out.push(`| ${cell(item.name)} | \`${cell(item.file)}\` | ${formatMs(item.durationMs)} |`);
    out.push('');
  }

  out.push(`## ${section++}. 能力矩阵（按能力维度的场景覆盖）`, '');
  const ids = catalog.suites.map(suite => suite.id);
  out.push(`| 能力 | ${catalog.suites.map(suite => cell(suite.name)).join(' | ')} | 合计 | 自动 | 本次通过率 |`);
  out.push(`| --- | ${ids.map(() => '---:').join(' | ')} | ---: | ---: | ---: |`);
  for (const row of Object.values(catalog.capabilities)) {
    if (!row.total) continue;
    const counts = ids.map(id => (row.bySuite[id] ? row.bySuite[id] : '·')).join(' | ');
    out.push(`| ${row.zh}（${row.key}）：${cell(row.hint)} | ${counts} | ${row.total} | ${row.automated} | ${row.executed ? pct(row.passed, row.executed) : '—'} |`);
  }
  out.push('');
  out.push('> 一个场景可命中多个能力维度；「自动」指本机无需模拟器/真机即可复跑。', '');

  out.push(`## ${section++}. 泛化能力评估（防过拟合）`, '');
  out.push('AI 改代码时最容易发生的事，是把系统调成“只在这几个场景上对”。这一层把场景按“平时能不能看”分开，评估只看留出、变体和未见场景，避免用一个不断被针对的集合给自己打分。', '');
  out.push('### 场景分层', '');
  out.push('| 层 | 定义 | 场景 | 实跑 | 通过 | 失败 | 通过率 | 使用方式 |');
  out.push('| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |');
  for (const slice of gen.slices) {
    if (!slice.scenarios) continue;
    out.push(`| ${slice.zh} | ${slice.key} | ${slice.scenarios} | ${slice.executed} | ${slice.pass} | ${slice.fail} | ${slice.passRate == null ? '—' : slice.passRate + '%'} | ${slice.use} |`);
  }
  out.push('');
  out.push('### 泛化指标', '');
  const dev = gen.slices.find(item => item.key === 'development');
  const holdout = gen.slices.find(item => item.key === 'holdout');
  const variant = gen.slices.find(item => item.key === 'variant');
  out.push(`- 开发集 → 留出集通过率差：${gen.gap == null ? '—（本轮缺一侧结果）' : `${gen.gap >= 0 ? '+' : ''}${gen.gap} 个百分点`}（开发集 ${dev?.passRate ?? '—'}%，留出集 ${holdout?.passRate ?? '—'}%）。差距为正且越大，越可能是过拟合。`);
  out.push(`- 变体通过率：${variant?.passRate == null ? '—' : variant.passRate + '%'}（场景内角色/文案/时序已替换）。`);
  out.push(`- 能力维度覆盖：${gen.diversity.capabilities}/${gen.diversity.capabilityTotal}（留出集覆盖：${gen.diversity.holdoutCapabilities.map(key => CAPS[key]?.zh ?? key).join('、') || '无'}；未见场景覆盖：${gen.diversity.unseenCapabilities.map(key => CAPS[key]?.zh ?? key).join('、') || '无'}）。`);
  out.push(`- 工具覆盖：${gen.diversity.tools}%；运行环境：${gen.diversity.environments} 类（本机 / 模拟器 / 真机）。`);
  out.push('');
  out.push('### 反过拟合协议', '');
  out.push('1. **留出集冻结**：`holdout` 场景只在评估日跑，平时不跑、不照着它改代码；把它当作考试题，而不是练习题。');
  out.push('2. **变体必跑**：每次评估都跑 `POKI_EVAL_VARIANT=1` 的变体场景；只看原场景通过没有意义。');
  out.push('3. **每轮加新题**：每次能力评估至少新增 1–2 个此前没见过的场景（Gym 新屏、真机清单新条目或新的合成页面），加入后只跑一次就归档为留出。');
  out.push('4. **盲选场景**：评估用的场景由没有参与实现的人挑，或从 Gym/真机清单里随机抽；不要由写代码的人指定。');
  out.push('5. **按能力维度打分**：报告每个能力维度的通过率（第 2 节），不要只报一个总数；某个维度为 0 比总体 98% 更重要。');
  out.push('6. **区分特例与通病**：失败的修复必须是通用的（改机制），如果只能“针对这个场景”修，就把该场景记为过拟合证据。');
  out.push('7. **审计测试改动**：一次改动如果修改的是测试期望值而不是被测行为，视为过拟合信号，需要说明理由。');
  out.push('8. **趋势看留出集**：用 `.runtime/test-catalog/history.jsonl` 对比多次评估的留出集通过率与变体通过率，而不是开发集。');
  out.push('');
  if (gen.warnings.length) {
    out.push('### 本轮自动提示', '');
    for (const warning of gen.warnings) out.push(`- ${warning}`);
    out.push('');
  }

  out.push(`## ${section++}. 工具覆盖（MCP 工具目录 ${catalog.toolCoverage.total} 项）`, '');
  const cov = catalog.toolCoverage;
  out.push(`- **提及覆盖**：${cov.mentions.covered}/${cov.total}（${cov.mentions.percent}%）。工具名是否在单元测试或文档里出现过；出现清单断言也会算，所以这个数偏高。`);
  out.push(`- **端到端覆盖**：${cov.exercised.covered}/${cov.total}（${cov.exercised.percent}%）。工具是否在 Gym scorecard、动作效率场景、真机清单或验收脚本里被真实驱动；判断能力面看这个。`);
  if (cov.mentions.uncovered.length) out.push(`\n连提及都没有的工具（${cov.mentions.uncovered.length}）：${cov.mentions.uncovered.map(tool => `\`${tool}\``).join('、')}。`);
  if (cov.exercised.uncovered.length) out.push(`\n端到端尚未驱动的工具（${cov.exercised.uncovered.length}）：${cov.exercised.uncovered.map(tool => `\`${tool}\``).join('、')}。`);
  out.push('');

  for (const suite of catalog.suites) {
    out.push(`## ${section++}. ${suite.name}`, '');
    out.push(`- 入口：\`${suite.entry}\``);
    out.push(`- 场景：${suite.metrics.scenarios}（通过 ${suite.metrics.pass}，失败 ${suite.metrics.fail}，超时 ${suite.metrics.timeout}，未跑 ${suite.metrics['not-run'] + suite.metrics.error}），墙钟 ${formatMs(suite.durationMs)}`);
    if (suite.metrics.medianMs) out.push(`- 单场景耗时：中位 ${formatMs(suite.metrics.medianMs)}，P95 ${formatMs(suite.metrics.p95Ms)}，最长 ${formatMs(suite.metrics.maxMs)}`);
    out.push('');
    renderSuiteScenarios(out, suite);
  }

  out.push('## 指标定义', '');
  out.push('- **场景数**：一条可独立判定的测试/检查（Node 的每一条 test 与 subtest、每个 XCTest 方法、每个 `#[test]`、每个 Gym 屏与 scorecard 步骤、每个人工检查项）。');
  out.push('- **实跑**：本次真实执行并拿到结果；**超时**：文件在限定时间内没有返回结果（进程被终止）；**未跑**：静态盘点或需要模拟器/真机。');
  out.push('- **通过率**：通过 /（通过 + 失败），失败包含断言失败、超时与执行错误。');
  out.push('- **墙钟**：整套运行的实际耗时（并行执行，不是各场景耗时之和）。');
  out.push('- **能力维度**：观察、操作、批量与等待、会话与传输、安装与配对、Agent 端、安全与审批、稳定性与容错、效率与资源、诊断与证据。');
  out.push('- **泛化层**：回归（平时可见）、开发集（调参可见）、留出集（只在评估日）、变体（换表面特征）、未见场景（模拟器/真机）、真机人工、验收脚本。');
  out.push('- **工具覆盖**：MCP 工具目录中的工具名是否出现在测试源码或验收文档里（只说明“有覆盖证据”，不代表参数级全覆盖）。', '');

  out.push('## 评估建议', '');
  out.push('### 日常回归（改动时）');
  out.push('1. `node bin/test-catalog.mjs`：看第 1 节通过率和墙钟是否回退，对比 `.runtime/test-catalog/history.jsonl` 的上一条记录。');
  out.push('2. 改完 `desktop/`、`native/bridge` 或 `native/launcher`：加 `--rust`，关注 Rust 套件的失败项与构建状态（`native/launcher` 需要先跑 `native/launcher/fetch-idevice.sh`）。');
  out.push('3. 只看回归与开发集，不要为了留出集通过而改代码（见第 3 节协议）。');
  out.push('');
  out.push('### 评估日（完整一次，判断能力有没有真的长进）');
  out.push('1. 本机：`node bin/test-catalog.mjs --rust`（完整跑包含留出集与变体；把输出 JSON、本文件和历史记录一起留档）。');
  out.push('2. 模拟器：按 `.github/workflows/ios-gym.yml` 的 `scorecard`（runner 路径）和 `scorecard-inprocess` 跑 Gym；本机等价流程见 `native/ios-gym/README.md`（`xcodebuild build` + `swift run -c release poki-gym-check`）。');
  out.push('3. 真机：按 `docs/device-test-checklist.md` 顺序执行，把每一步的结果和用时写回对应行。');
  out.push('4. 比较三组结果：留出集/变体通过率（第 3 节）、Gym scorecard 的失败项、真机清单的未通过项；只看这组“没被针对性调过”的数字。');
  out.push('5. 把本文件与 `test-scenarios.json` 提交为该版本的能力基线；`--render docs/test-scenarios.json` 可在不重跑的情况下按新模板重排文档。');
  out.push('');
  out.push('### 新增场景');
  out.push('- 新增 Node 测试文件：放进 `test/`（或 `agent/test/`）即可，下次运行自动出现在目录里；在 `bin/test-catalog.mjs` 的 `MAIN_FILE_TAGS`/`AGENT_FILE_TAGS` 里补一行能力标签。');
  out.push('- 新增 Gym 屏或 scorecard 步骤：改 `native/ios-gym`，目录会自动重新盘点。');
  out.push('- 新增人工检查项：写进 `docs/device-test-checklist.md`，按 `- [ ]` 条目统计。');
  out.push('- 新增后先跑一轮记下结果，再把它标记为留出/变体（只在评估日跑），避免它退化成第二个开发集。');
  out.push('');

  if (catalog.gaps.length) {
    out.push('## 已知缺口与不稳定项', '');
    for (const gap of catalog.gaps) out.push(`- ${gap}`);
    out.push('');
  }
  return out.join('\n');
}

function renderSuiteScenarios(out, suite) {
  if (!suite.scenarios.length) { out.push('（无）', ''); return; }
  if (suite.kind === 'file') {
    const files = [...new Set(suite.scenarios.map(scenario => scenario.file))];
    for (const file of files) {
      const scenarios = suite.scenarios.filter(scenario => scenario.file === file);
      const pass = scenarios.filter(scenario => scenario.status === 'pass').length;
      const fail = scenarios.filter(scenario => scenario.status === 'fail').length;
      const timeout = scenarios.filter(scenario => scenario.status === 'timeout').length;
      const ms = scenarios.reduce((total, scenario) => total + scenario.durationMs, 0);
      out.push(`**\`${file}\`** — ${scenarios.length} 场景（通过 ${pass}，失败 ${fail}，超时 ${timeout}，合计 ${formatMs(ms)}）`, '');
      out.push('| 场景 | 能力 | 结果 | 耗时 |');
      out.push('| --- | --- | --- | ---: |');
      for (const scenario of scenarios) {
        out.push(`| ${cell(scenario.name)}${scenario.detail && scenario.status !== 'pass' ? ` — ${cell(scenario.detail)}` : ''} | ${capText(scenario.capabilities)} | ${statusText(scenario.status)}${scenario.flaky ? '（flaky）' : ''} | ${scenario.durationMs ? formatMs(scenario.durationMs) : '—'} |`);
      }
      out.push('');
    }
    return;
  }
  if (suite.kind === 'scenario' || suite.kind === 'simulator' || suite.kind === 'acceptance' || suite.kind === 'manual' || suite.kind === 'playbook') {
    out.push('| 场景 | 位置 | 能力 | 结果 | 说明 |');
    out.push('| --- | --- | --- | --- | --- |');
    for (const scenario of suite.scenarios) {
      const where = scenario.file ? `\`${scenario.file}${scenario.line ? `:${scenario.line}` : ''}\`` : '—';
      out.push(`| ${cell(scenario.name)} | ${where} | ${capText(scenario.capabilities)} | ${statusText(scenario.status)} | ${cell(scenario.detail ?? '')} |`);
    }
    out.push('');
    return;
  }
  if (suite.kind === 'xctest' || suite.kind === 'rust') {
    const files = [...new Set(suite.scenarios.map(scenario => scenario.file))];
    for (const file of files) {
      const scenarios = suite.scenarios.filter(scenario => scenario.file === file);
      const pass = scenarios.filter(scenario => scenario.status === 'pass').length;
      const fail = scenarios.filter(scenario => scenario.status === 'fail').length;
      out.push(`**\`${file}\`** — ${scenarios.length} 场景${pass || fail ? `（通过 ${pass}，失败 ${fail}）` : ''}`, '');
      out.push('| 场景 | 行 | 能力 | 结果 |');
      out.push('| --- | ---: | --- | --- |');
      for (const scenario of scenarios) out.push(`| \`${cell(scenario.name)}\` | ${scenario.line || '—'} | ${capText(scenario.capabilities)} | ${statusText(scenario.status)}${scenario.detail ? ` — ${cell(scenario.detail)}` : ''} |`);
      out.push('');
    }
  }
}

function capText(capabilities = []) {
  return capabilities.map(key => CAPS[key]?.zh ?? key).join('、');
}

function statusText(status) {
  return `${STATE_ICON[status] ?? ''} ${STATE[status] ?? status}`.trim();
}

function cell(text) {
  return String(text ?? '').replace(/\|/g, '/').replace(/\n/g, ' ');
}

function formatMs(ms) {
  if (!ms) return '—';
  return ms >= 1000 ? `${(ms / 1000).toFixed(1)} s` : `${Math.round(ms)} ms`;
}

// ---------------------------------------------------------------------------------------------
// fs helpers
// ---------------------------------------------------------------------------------------------

async function readText(file) {
  return readFile(join(ROOT, file), 'utf8');
}

function lineOf(source, pattern) {
  const index = source.search(pattern);
  if (index < 0) return 0;
  return source.slice(0, index).split('\n').length;
}

function escapeRegExp(text) {
  return String(text).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function walk(dir, filter) {
  const results = [];
  const entries = await readdir(join(ROOT, dir), { withFileTypes: true }).catch(() => []);
  for (const entry of entries) {
    if (entry.name === 'node_modules' || entry.name === 'target' || entry.name === '.runtime' || entry.name.startsWith('.')) continue;
    const file = join(dir, entry.name);
    if (entry.isDirectory()) results.push(...await walk(file, filter));
    else if (filter(entry.name)) results.push(file);
  }
  return results.sort();
}

await main();

function spawnCollect(command, args, { cwd = ROOT, env = process.env, timeoutMs = 300000 } = {}) {
  return new Promise(resolvePromise => {
    const child = spawn(command, args, { cwd, env, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => { child.kill('SIGKILL'); }, timeoutMs);
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('close', code => { clearTimeout(timer); resolvePromise({ status: code === 0 ? 'ok' : 'fail', code, stdout, stderr }); });
    child.on('error', error => { clearTimeout(timer); resolvePromise({ status: 'error', code: -1, stdout, stderr: error.message }); });
  });
}
