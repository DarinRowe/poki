#!/usr/bin/env node
// Measures how a brand-new Claude Code or Codex CLI window does with the Poki tools it is given,
// on disposable simulators only. A window sees the tool descriptions and the task, nothing else.
//
//   node bin/eval-first-call.mjs prepare --udids A,B --fixture path/to/PokiMCPFixture.app
//   node bin/eval-first-call.mjs run --udids A,B --out DIR --root new=PATH --root single=PATH \
//        --clients claude,codex --tasks counter,form,wrong_target --repeat 5
//   node bin/eval-first-call.mjs report --out DIR
//
// To compare with and without the skill, give both groups the same root and one of them the skill:
//   --root with=. --root without=. --skill with=skills/poki-mcp --tasks T1,T2,T3,T4,T5
// T1 needs the Fernbrook test app installed, and Reminders, Safari and Messages past their first-run screens.
//
// In --udids, A+B makes one lane of two simulators, which the tasks that need two devices require.
import { spawn, execFile } from 'node:child_process';
import { once } from 'node:events';
import { createHash } from 'node:crypto';
import { appendFile, chmod, cp, mkdir, readFile, readdir, rm, symlink, writeFile } from 'node:fs/promises';
import { homedir, loadavg } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { parseArgs } from 'node:util';

const here = resolve(fileURLToPath(import.meta.url), '../..');
const run = promisify(execFile);
const bundle = 'local.pokimcp.fixture';
const ax = async (udid, root = here) => {
  const { stdout } = await new Promise((done, fail) => {
    const child = execFile(join(root, 'build/simulator'), [], { maxBuffer: 64 << 20 }, (error, out, err) => error ? fail(error) : done({ stdout: out, stderr: err }));
    child.stdin.end(JSON.stringify({ id: udid, op: 'ax' }));
  });
  return JSON.parse(stdout);
};

const simctl = (...args) => run('/usr/bin/xcrun', ['simctl', ...args]);
const fernbrook = 'local.pokimcp.fixture';
// Reading the store proves a reminder was saved, and how many times, without driving the app under test.
async function savedReminders(udid, title) {
  const { stdout: groups } = await simctl('get_app_container', udid, 'com.apple.reminders', 'groups');
  const stores = join(groups.split('\n').find(line => line.startsWith('group.com.apple.reminders')).split('\t')[1], 'Container_v1/Stores');
  const counts = await Promise.all((await readdir(stores)).filter(name => name.endsWith('.sqlite')).map(async name => {
    const sql = `select count(*), coalesce(sum(ZTITLE = '${title}'), 0) from ZREMCDREMINDER where ZMARKEDFORDELETION = 0`;
    const { stdout } = await run('/usr/bin/sqlite3', [`file:${join(stores, name)}?mode=ro`, sql]).catch(() => ({ stdout: '0|0' }));
    return stdout.trim().split('|').map(Number);
  }));
  return { saved: counts.reduce((sum, [, match]) => sum + match, 0), list_length: counts.reduce((sum, [all]) => sum + all, 0) };
}
// Safari shows a passing notice where the address goes, so this waits for the address to come back.
async function safariAddress(udid) {
  for (const started = performance.now(); performance.now() - started < 15000; await new Promise(done => setTimeout(done, 500))) {
    const tree = await ax(udid).catch(() => ({ elements: [] }));
    const address = tree.elements.find(element => element.label === '地址')?.value?.replace(/\u200e/g, '');
    if (address) return address;
  }
  return null;
}
// Sent bubbles are missing from the accessibility tree and the simulator has no message store, so the screen is the record.
async function sentBubbles(udid, dir, word) {
  const shot = join(dir, 'final.png');
  await simctl('io', udid, 'screenshot', shot);
  const { stdout } = await run(join(here, 'build/ocr'), [shot]);
  const lines = JSON.parse(stdout).map(item => item.text);
  return { ocr_text: lines, sent: lines.filter(line => line.includes(word)).length };
}

const tasks = {
  T1: {
    bundle: fernbrook,
    arrange: udid => simctl('spawn', udid, 'defaults', 'delete', fernbrook, 'draft').catch(() => {}),
    prompt: (_, word) => `在 Fernbrook 的测试文字框填写“${word}”，确认已保存的文字，不做其他操作。`,
    oracle: ({ foreground, labels, reply, word }) => foreground === fernbrook && labels.includes(`已保存：${word}`) && reply.includes(word),
  },
  T2: {
    bundle: 'com.apple.reminders',
    prompt: (_, word) => `在系统提醒事项中新建并保存一条虚构提醒“${word}”，不设置日期，确认提醒已经创建。`,
    inspect: ({ udid, word }) => savedReminders(udid, word),
    oracle: ({ saved, reply, word }) => saved === 1 && reply.includes(word),
  },
  T3: {
    bundle: 'com.apple.Preferences',
    prompt: () => '在系统设置进入“通用 > 关于本机”，读出“机型名称”的值，不修改设置。',
    oracle: ({ foreground, labels, reply }) => foreground === 'com.apple.Preferences' && labels.some(label => label.includes('iPhone 17 Pro')) && reply.includes('iPhone 17 Pro'),
  },
  T4: {
    bundle: 'com.apple.mobilesafari',
    // Both pages show the same words, so only the address tells them apart.
    arrange: async udid => {
      await simctl('openurl', udid, 'https://example.org');
      const address = await safariAddress(udid);
      if (address !== 'example.org') throw new Error(`Safari did not reach the other Example Domain page: ${address}.`);
    },
    prompt: () => '在 Safari 打开 https://example.com，读出页面上第一段英文的内容，不进行其他操作。',
    inspect: async ({ udid }) => ({ address: await safariAddress(udid) }),
    oracle: ({ foreground, reply, address }) => foreground === 'com.apple.mobilesafari' && address === 'example.com' && /documentation examples/i.test(reply),
  },
  // Only this task has a send step after the text, so it measures filling and sending in one batch.
  T5: {
    bundle: 'com.apple.MobileSMS',
    prompt: (_, word) => `在系统信息 App 里打开和 +1 (555) 564-8583 的对话，发送虚构内容“${word}”，确认已发出，不做其他操作。`,
    inspect: ({ udid, dir, word }) => sentBubbles(udid, dir, word),
    oracle: ({ foreground, sent, reply, word }) => foreground === 'com.apple.MobileSMS' && sent === 1 && reply.includes(word),
  },
  counter: {
    prompt: `在 iOS 模拟器上打开测试程序（包名 ${bundle}），把 Increment 按钮点 5 次，然后告诉我屏幕上显示的计数。`,
    oracle: ({ state, labels, reply }) => state?.count === 5 && labels.includes('Count: 5') && /5/.test(reply),
  },
  form: {
    prompt: `在 iOS 模拟器上打开测试程序（包名 ${bundle}）。在输入框里填 hello poki，点 Open Detail 进详情页，再返回，然后点 Show Alert，在弹窗里点 OK，最后告诉我输入框上面那行文字现在是什么。`,
    oracle: ({ state, labels, reply }) => state?.text === 'hello poki' && labels.includes('Alert accepted') && /Alert accepted/i.test(reply),
  },
  wrong_target: {
    prompt: `在 iOS 模拟器上打开测试程序（包名 ${bundle}），把 Increment 按钮点 2 次，再点 Open Details 按钮进入详情页，停在详情页，告诉我页面标题。`,
    oracle: ({ state, labels, reply }) => state?.count === 2 && labels.includes('Detail') && !labels.includes('Increment') && /Detail/i.test(reply),
  },
  scroll_end: {
    prompt: `在 iOS 模拟器上打开测试程序（包名 ${bundle}），一直往下滑到页面滑不动为止，然后点一次 Bottom target 按钮。不要点别的按钮。最后告诉我屏幕最下面那个按钮叫什么。`,
    oracle: ({ state, reply }) => state?.count === 1 && /Create test crash/i.test(reply),
  },
  scroll: {
    prompt: `在 iOS 模拟器上打开测试程序（包名 ${bundle}），一直往下滑到 Bottom target 按钮，点它一次。不要点别的按钮。然后滑回顶部，告诉我屏幕上显示的计数。`,
    oracle: ({ state, labels, reply }) => state?.count === 1 && labels.includes('Count: 1') && /1/.test(reply),
  },
  named_device: {
    devices: 2,
    prompt: ([target]) => `这台 Mac 上开着两台 iOS 模拟器。在名为 ${target} 的模拟器上打开测试程序（包名 ${bundle}），把 Increment 按钮点 3 次，然后告诉我屏幕上显示的计数。另一台不要动。`,
    oracle: ({ state, labels, reply, others }) => state?.count === 3 && labels.includes('Count: 3') && /3/.test(reply) && !others[0].state && others[0].foreground !== bundle,
  },
  two_devices: {
    devices: 2,
    prompt: ([first, second]) => `这台 Mac 上开着两台 iOS 模拟器，${first} 和 ${second}。在 ${first} 上打开测试程序（包名 ${bundle}），把 Increment 按钮点 1 次；再在 ${second} 上打开同一个测试程序，把 Increment 按钮点 2 次。最后告诉我两台模拟器各自显示的计数。`,
    oracle: ({ state, reply, others }) => state?.count === 1 && others[0].state?.count === 2 && /1/.test(reply) && /2/.test(reply),
  },
};

const fastEntries = new Set(['execute_plan', 'batch_commands']);
const discovery = new Set(['ToolSearch', 'tool_search', 'list_mcp_resources', 'list_mcp_resource_templates', 'Skill', 'shell']);
// Anything else is a UI action, so "the first UI action" means the same thing in every group.
const setup = new Set(['list_devices', 'select_device', 'start_simulator', 'get_device_info', 'poki_mcp_status', 'launch_app', 'terminate_app', 'list_apps', 'list_elements', 'observe_device', 'take_screenshot', 'get_foreground_app', 'acquire_device', 'renew_device', 'release_device', 'cancel_device', 'wait', 'wait_for']);
const looks = new Set(['list_elements', 'observe_device', 'take_screenshot', 'get_foreground_app', 'wait_for']);
const shortName = name => name.replace(/^mcp__poki-mcp__/, '');
export const overlapRounds = calls => {
  let rounds = 0, previousEnd = -Infinity;
  for (const call of [...calls].sort((a, b) => a.startedAt - b.startedAt)) {
    if (call.startedAt >= previousEnd) rounds++;
    previousEnd = Math.max(previousEnd, call.endedAt ?? call.startedAt);
  }
  return rounds;
};

async function makeShims(dir) {
  await mkdir(dir, { recursive: true });
  const files = {
    python3: `#!/bin/sh\necho '[]'\n`,
    idevice: `#!/bin/sh\necho 'physical devices are disabled in this rig' >&2\nexit 1\n`,
    osascript: `#!/bin/sh\necho cancelled\n`,
    xcrun: `#!/bin/sh
case "$1" in
  devicectl) echo 'physical devices are disabled in this rig' >&2; exit 1;;
  simctl)
    case "$2" in
      list) /usr/bin/xcrun "$@" | /usr/bin/python3 -c 'import json,os,sys
d=json.load(sys.stdin)
if "devices" in d: d["devices"]={r:[x for x in v if x["udid"] in os.environ["POKI_EVAL_UDID"].split(",")] for r,v in d["devices"].items()}
json.dump(d,sys.stdout)'; exit $?;;
      create|delete|erase|clone|shutdown|pair|unpair|boot)
        named=
        for arg in "$@"; do case ",$POKI_EVAL_UDID," in *",$arg,"*) named=1;; esac; done
        [ -n "$named" ] || { echo "simctl $2 is limited to the rig simulators" >&2; exit 1; };;
    esac
    for arg in "$@"; do
      case "$arg" in
        [0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]-*-*-*-*) case ",$POKI_EVAL_UDID," in *",$arg,"*) ;; *) echo "simulator $arg is outside this rig" >&2; exit 1;; esac;;
      esac
    done;;
esac
exec /usr/bin/xcrun "$@"
`,
  };
  for (const [name, body] of Object.entries(files)) {
    await writeFile(join(dir, name), body);
    await chmod(join(dir, name), 0o755);
  }
  return dir;
}

async function startDaemon(root, stateDir, shims, udid) {
  const env = { ...process.env, POKI_MCP_STATE_DIR: stateDir, POKI_MCP_APPROVAL_MODE: 'allow', POKI_EVAL_UDID: udid, IDEVICE_TOOLS: join(shims, 'idevice'), PATH: `${shims}:${process.env.PATH}` };
  const child = spawn(process.execPath, [join(root, 'src/daemon.mjs'), '--port', '0'], { env, stdio: ['ignore', 'pipe', 'ignore'] });
  const lines = createInterface({ input: child.stdout });
  const [line] = await once(lines, 'line');
  lines.close();
  return { child, ready: JSON.parse(line), stateDir, root };
}

const claudeDenied = ['Bash', 'Edit', 'Write', 'Read', 'Glob', 'Grep', 'NotebookEdit', 'Task', 'Agent', 'WebFetch', 'WebSearch', 'Workflow', 'Monitor', 'CronCreate', 'CronDelete', 'CronList', 'DesignSync', 'EnterWorktree', 'ExitWorktree', 'PushNotification', 'RemoteTrigger', 'ReportFindings', 'ScheduleWakeup', 'SendMessage', 'TaskStop', 'ListAgents'];

// With a skill in the run both groups use the settings that let a window load one, and only the group given it finds it.
async function claudeWindow(prompt, daemon, cwd, { skill, skillRun }) {
  if (skill) await cp(skill, join(cwd, '.claude/skills', basename(skill)), { recursive: true });
  const config = { mcpServers: { 'poki-mcp': { command: process.execPath, args: [join(daemon.root, 'src/stdio.mjs')], env: { POKI_MCP_STATE_DIR: daemon.stateDir } } } };
  return { file: 'claude', cwd, env: process.env, args: ['-p', prompt, '--model', 'claude-opus-5-5', '--effort', 'high', '--setting-sources', skillRun ? 'project' : '', '--settings', '{"alwaysThinkingEnabled":true}', '--strict-mcp-config', '--mcp-config', JSON.stringify(config), ...(skillRun ? [] : ['--disable-slash-commands']), '--no-session-persistence', '--output-format', 'stream-json', '--verbose', '--dangerously-skip-permissions', '--disallowedTools', ...claudeDenied] };
}

// A throwaway CODEX_HOME keeps the team-wide AGENTS.md and the user's session list out of the test,
// and a throwaway HOME keeps ~/.agents/skills out. Codex reads a skill through its shell, which the
// read-only sandbox stops from reaching the simulators.
async function codexWindow(prompt, daemon, cwd, { skill, skillRun }) {
  const home = join(cwd, '.codex-home');
  await mkdir(join(cwd, '.home'), { recursive: true });
  await mkdir(home, { recursive: true });
  if (skill) await cp(skill, join(home, 'skills', basename(skill)), { recursive: true });
  await symlink(join(homedir(), '.codex/auth.json'), join(home, 'auth.json')).catch(error => { if (error.code !== 'EEXIST') throw error; });
  await writeFile(join(home, 'config.toml'), `model = "gpt-6-astra"
model_reasoning_effort = "high"
service_tier = "default"
approval_policy = "never"
sandbox_mode = "read-only"
check_for_update_on_startup = false
web_search = "disabled"

[features]
shell_tool = ${skillRun}
apps = false
memories = false
chronicle = false
goals = false

[mcp_servers.poki-mcp]
command = ${JSON.stringify(process.execPath)}
args = [${JSON.stringify(join(daemon.root, 'src/stdio.mjs'))}]
startup_timeout_sec = 30
tool_timeout_sec = 900
default_tools_approval_mode = "approve"

[mcp_servers.poki-mcp.env]
POKI_MCP_STATE_DIR = ${JSON.stringify(daemon.stateDir)}
`);
  return { file: 'codex', cwd, env: { ...process.env, CODEX_HOME: home, HOME: join(cwd, '.home') }, args: ['exec', '--json', '--ephemeral', '--skip-git-repo-check', '--ignore-rules', '-C', cwd, prompt] };
}
const windows = { claude: claudeWindow, codex: codexWindow };

function flatten(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return JSON.stringify(content ?? '');
  return content.map(block => block.type === 'text' ? block.text : `[${block.type}]`).join('\n');
}

const parsers = {
  claude(lines) {
    const rounds = new Set(), calls = new Map(); let reply = '', usage, cost, apiMs;
    for (const { at, event } of lines) {
      if (event.type === 'assistant') {
        rounds.add(event.message.id);
        for (const block of event.message.content) {
          if (block.type === 'tool_use') calls.set(block.id, { name: shortName(block.name), input: block.input, startedAt: at });
          if (block.type === 'text') reply = block.text;
        }
      } else if (event.type === 'user' && Array.isArray(event.message?.content)) {
        for (const block of event.message.content) if (block.type === 'tool_result' && calls.has(block.tool_use_id)) Object.assign(calls.get(block.tool_use_id), { endedAt: at, isError: !!block.is_error, text: flatten(block.content) });
      } else if (event.type === 'result') { usage = event.usage; cost = event.total_cost_usd; apiMs = event.duration_api_ms; if (event.result) reply = event.result; }
    }
    return { rounds: rounds.size, calls: [...calls.values()], reply, usage, cost, apiMs };
  },
  codex(lines) {
    const calls = new Map(); let reply = '', usage;
    for (const { at, event } of lines) {
      const item = event.item;
      if (event.type === 'item.started' && item?.type === 'command_execution') calls.set(item.id, { name: 'shell', input: { command: item.command }, startedAt: at });
      else if (event.type === 'item.completed' && item?.type === 'command_execution') Object.assign(calls.get(item.id) ?? {}, { endedAt: at, text: item.aggregated_output });
      else if (event.type === 'item.started' && item?.type === 'mcp_tool_call') calls.set(item.id, { name: item.tool, input: item.arguments, startedAt: at });
      else if (event.type === 'item.completed' && item?.type === 'mcp_tool_call') {
        const entry = calls.get(item.id) ?? { name: item.tool, input: item.arguments, startedAt: at };
        const text = item.error ? (item.error.message ?? JSON.stringify(item.error)) : flatten(item.result?.content);
        calls.set(item.id, { ...entry, endedAt: at, isError: item.status === 'failed' || !!item.error || !!item.result?.isError, text });
      } else if (event.type === 'item.completed' && item?.type === 'agent_message') reply = item.text;
      else if (event.type === 'turn.completed') usage = event.usage;
    }
    // codex exec does not mark model responses, so count overlapping calls as one and add the closing reply.
    return { rounds: overlapRounds([...calls.values()]) + 1, calls: [...calls.values()], reply, usage };
  },
};

async function resetLane(udid, keyboard, task) {
  await run('/usr/bin/xcrun', ['simctl', 'terminate', udid, task.bundle ?? bundle]).catch(() => {});
  // The new build switches the keyboard to en_US and that outlives the session, so every session
  // starts from the same layout or the other groups would inherit the fix.
  await run('/usr/bin/xcrun', ['simctl', 'keyboard', udid, keyboard]);
  if (task.bundle) { await task.arrange?.(udid); return null; }
  const { stdout } = await run('/usr/bin/xcrun', ['simctl', 'get_app_container', udid, bundle, 'data']);
  await rm(join(stdout.trim(), 'Documents/fixture-state.json'), { force: true });
  return join(stdout.trim(), 'Documents/fixture-state.json');
}

async function oracle(lane, statePaths, reply, task, context) {
  const [main, ...others] = await Promise.all(lane.devices.map(async (udid, index) => {
    const state = statePaths[index] ? await readFile(statePaths[index], 'utf8').then(JSON.parse).catch(() => null) : null;
    const tree = await ax(udid).catch(error => ({ elements: [], error: error.message }));
    const labels = tree.elements.flatMap(element => [element.label, element.value].filter(value => typeof value === 'string'));
    return { state, foreground: tree.foreground?.bundle_id ?? tree.bundle_id ?? null, labels, axError: tree.error };
  }));
  // A simulator's name can hold the digit the answer has to mention.
  const answer = lane.names.reduce((text, name) => text.replaceAll(name, ''), reply ?? '');
  const brief = ({ labels, ...rest }) => ({ ...rest, labels: labels.slice(0, 60) });
  const inspected = await tasks[task].inspect?.({ udid: lane.devices[0], ...context }) ?? {};
  return { pass: tasks[task].oracle({ ...main, ...inspected, ...context, reply: answer, others }), ...brief(main), ...inspected, others: others.map(brief) };
}

export function pairedText({ task, client, round }) {
  const seed = JSON.stringify([task, client, round]);
  return `Cedar ${createHash('sha256').update(seed).digest('hex').slice(0, 8).toUpperCase()}`;
}

export function tokenUsage(client, usage) {
  if (!usage || !Number.isFinite(usage.input_tokens) || !Number.isFinite(usage.output_tokens)) return null;
  const read = client === 'claude' ? usage.cache_read_input_tokens : usage.cached_input_tokens;
  const write = client === 'claude' ? usage.cache_creation_input_tokens : 0;
  const cacheRead = Number.isFinite(read) ? read : null;
  const cacheWrite = Number.isFinite(write) ? write : null;
  const input = client === 'claude'
    ? cacheRead === null || cacheWrite === null ? null : usage.input_tokens + cacheRead + cacheWrite
    : usage.input_tokens;
  const uncached = client === 'claude'
    ? cacheWrite === null ? null : usage.input_tokens + cacheWrite
    : cacheRead === null ? null : usage.input_tokens - cacheRead;
  return { input, cached_input: cacheRead, uncached_input: uncached,
    output: usage.output_tokens, total: input === null ? null : input + usage.output_tokens };
}

export function toolWallTime(calls) {
  const intervals = calls.filter(call => Number.isFinite(call.startedAt) && Number.isFinite(call.endedAt))
    .map(call => [call.startedAt, call.endedAt]).sort((a, b) => a[0] - b[0]);
  let elapsed = 0, end = -Infinity;
  for (const [start, finish] of intervals) {
    elapsed += Math.max(0, finish - Math.max(start, end));
    end = Math.max(end, finish);
  }
  return Math.round(elapsed);
}

export function summarize(job, parsed, total_ms, timedOut, verdict) {
  const device = parsed.calls.filter(call => !discovery.has(call.name));
  const firstCall = device[0], first = device.find(call => !setup.has(call.name)), firstFast = device.find(call => fastEntries.has(call.name) || call.name === job.fastEntry);
  const errorText = device.filter(call => call.isError).map(call => ({ tool: call.name, text: String(call.text).slice(0, 4000), input: call.input }));
  // fill can answer without an error and still leave the wrong text in the field.
  const wrongFill = call => /"text_verified":\s*false/.test(String(call.text)) && (call.name === 'fill' || call.name === 'batch_commands' && JSON.stringify(call.input ?? {}).includes('"fill"'));
  const firstError = device.findIndex(call => call.isError);
  const afterError = firstError >= 0 ? device[firstError + 1] : undefined;
  const afterFirstError = firstError >= 0 ? device.slice(firstError + 1) : [];
  const nextAction = afterFirstError.find(call => !setup.has(call.name));
  return {
    ...job, total_ms, timed_out: timedOut, oracle_pass: verdict.pass, oracle: { state: verdict.state, labels: verdict.labels, axError: verdict.axError, others: verdict.others, foreground: verdict.foreground, saved: verdict.saved, list_length: verdict.list_length, address: verdict.address, sent: verdict.sent, ocr_text: verdict.ocr_text },
    calls: parsed.calls.map(({ name, input, startedAt, endedAt, isError }) => ({ name, input, startedAt, endedAt, isError })),
    skill_loaded: parsed.calls.some(call => call.name === 'Skill' || call.name === 'shell' && /SKILL\.md/.test(call.input?.command ?? '')),
    model_rounds: parsed.rounds, tool_calls: device.length, discovery_calls: parsed.calls.length - device.length,
    tool_errors: errorText.length, errors: errorText,
    tools: device.map(call => call.name),
    first_call: firstCall ? { tool: firstCall.name, ok: !firstCall.isError && !wrongFill(firstCall) } : null,
    first_ui_action: first ? { tool: first.name, ok: !first.isError && !wrongFill(first) } : null,
    quiet_failures: device.filter(call => !call.isError && wrongFill(call)).length,
    look_calls: device.filter(call => looks.has(call.name)).length, scroll_calls: device.filter(call => call.name === 'scroll' || call.name === 'swipe').length,
    first_fast_call: firstFast ? { tool: firstFast.name, ok: !firstFast.isError } : null,
    fast_entry_calls: device.filter(call => fastEntries.has(call.name) || call.name === job.fastEntry).length,
    next_call_after_first_error: afterError ? { tool: afterError.name, ok: !afterError.isError } : null,
    next_action_after_first_error: nextAction ? { tool: nextAction.name, ok: !nextAction.isError, calls_between: afterFirstError.indexOf(nextAction) } : null,
    tool_ms: Math.round(device.reduce((sum, call) => sum + (call.endedAt ?? call.startedAt) - call.startedAt, 0)),
    tool_wall_ms: toolWallTime(device),
    usage: parsed.usage ?? null, tokens: tokenUsage(job.client, parsed.usage), cost_usd: parsed.cost ?? null, api_ms: parsed.apiMs ?? null, reply: parsed.reply,
  };
}

async function runJob(job, lane, options) {
  const dir = join(options.out, 'runs', options.attempt > 1 ? `${job.id}-try${options.attempt}` : job.id);
  await mkdir(dir, { recursive: true });
  const statePaths = await Promise.all(lane.devices.map(udid => resetLane(udid, options.keyboard, tasks[job.task])));
  const { prompt } = tasks[job.task];
  const word = pairedText(job);
  const window = await windows[job.client](typeof prompt === 'function' ? prompt(lane.names, word) : prompt, lane.daemons[job.group], dir, { skill: options.skills[job.group], skillRun: Object.keys(options.skills).length > 0 });
  job = { ...job, lane: lane.udid, load1_at_start: loadavg()[0] };
  const started = performance.now(), lines = [];
  const raw = join(dir, 'stream.jsonl');
  const child = spawn(window.file, window.args, { cwd: window.cwd, env: window.env, stdio: ['ignore', 'pipe', 'pipe'] });
  const closed = once(child, 'close');
  let stderr = '';
  child.stderr.on('data', chunk => { stderr += chunk; });
  let timedOut = false;
  const timer = setTimeout(() => { timedOut = true; child.kill('SIGTERM'); setTimeout(() => child.kill('SIGKILL'), 5000).unref(); }, options.timeoutMs);
  const reader = createInterface({ input: child.stdout });
  for await (const line of reader) {
    await appendFile(raw, line + '\n');
    try { lines.push({ at: performance.now(), event: JSON.parse(line) }); } catch { /* A CLI banner line is kept in the raw file only. */ }
  }
  await closed.catch(() => {});
  clearTimeout(timer);
  const total = Math.round(performance.now() - started);
  await writeFile(join(dir, 'stderr.txt'), stderr);
  const parsed = parsers[job.client](lines);
  const verdict = await oracle(lane, statePaths, parsed.reply, job.task, { word, dir });
  const unreachable = !parsed.calls.length && lines.some(({ event }) => event.type === 'turn.failed' || event.type === 'result' && event.is_error);
  const summary = { ...summarize(job, parsed, total, timedOut, verdict), client_unreachable: unreachable, attempt: options.attempt };
  await writeFile(join(dir, 'summary.json'), JSON.stringify(summary, null, 2));
  await appendFile(join(options.out, unreachable ? 'unreachable.jsonl' : 'results.jsonl'), JSON.stringify(summary) + '\n');
  console.log(`${job.id}: ${verdict.pass ? 'PASS' : 'FAIL'} ${(total / 1000).toFixed(1)}s rounds=${parsed.rounds} calls=${summary.tool_calls} errors=${summary.tool_errors} first_call=${summary.first_call?.tool}:${summary.first_call?.ok} first_ui=${summary.first_ui_action?.tool}:${summary.first_ui_action?.ok} load=${Math.round(job.load1_at_start)}`);
  return summary;
}

function schedule({ groups, clients, taskNames, repeat, fastEntry }) {
  const jobs = [];
  for (let round = 1; round <= repeat; round++) {
    const rotated = groups.map((_, index) => groups[(index + round - 1) % groups.length]);
    for (const task of taskNames) for (const client of clients) for (const group of rotated) {
      jobs.push({ id: `${group}-${client}-${task}-${round}`, group, client, task, round, fastEntry: fastEntry[group] });
    }
  }
  return jobs;
}

function median(values) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b), middle = sorted.length >> 1;
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}
const range = values => values.length ? `${Math.min(...values)}–${Math.max(...values)}` : '-';

export async function report(out) {
  const rows = (await readFile(join(out, 'results.jsonl'), 'utf8')).trim().split('\n').map(line => JSON.parse(line));
  const unreachable = (await readFile(join(out, 'unreachable.jsonl'), 'utf8').catch(() => '')).trim().split('\n').filter(Boolean).length;
  const header = '| 客户端 | 任务 | 组 | 次数 | 任务成功 | 第一次设备调用成功 | 第一次界面操作成功 | 第一次快速入口调用成功 | 失败次数（报错＋填错） | 往返中位（范围） | 总耗时中位秒（范围） | 工具耗时中位秒 | 看屏次数中位 | 滚动次数中位 | 出错后下一次调用就改对 |';
  const line = (client, task, group, subset) => {
    const fast = subset.filter(row => row.first_fast_call);
    return `| ${client} | ${task} | ${group} | ${subset.length} | ${subset.filter(row => row.oracle_pass).length}/${subset.length} | ${subset.filter(row => row.first_call?.ok).length}/${subset.length} | ${subset.filter(row => row.first_ui_action?.ok).length}/${subset.length} | ${fast.filter(row => row.first_fast_call.ok).length}/${fast.length} | ${subset.reduce((sum, row) => sum + row.tool_errors, 0)}＋${subset.reduce((sum, row) => sum + (row.quiet_failures ?? 0), 0)} | ${median(subset.map(row => row.model_rounds))} (${range(subset.map(row => row.model_rounds))}) | ${(median(subset.map(row => row.total_ms)) / 1000).toFixed(1)} (${range(subset.map(row => Math.round(row.total_ms / 1000)))}) | ${(median(subset.map(row => row.tool_ms)) / 1000).toFixed(1)} | ${median(subset.map(row => row.look_calls ?? 0))} | ${median(subset.map(row => row.scroll_calls ?? 0))} | ${subset.filter(row => row.next_action_after_first_error?.ok && row.next_action_after_first_error.calls_between === 0).length}/${subset.filter(row => row.tool_errors).length} |`;
  };
  const lines = [header, '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|'];
  const distinct = field => [...new Set(rows.map(row => row[field]))].sort();
  for (const client of distinct('client')) for (const group of distinct('group')) {
    const subset = rows.filter(row => row.client === client && row.group === group);
    if (subset.length) lines.push(line(client, '**全部**', group, subset));
  }
  for (const client of distinct('client')) for (const task of distinct('task')) for (const group of distinct('group')) {
    const subset = rows.filter(row => row.client === client && row.task === task && row.group === group);
    if (subset.length) lines.push(line(client, task, group, subset));
  }
  lines.push('', '### Token 消耗', '',
    '| 客户端 | 任务 | 组 | 有 usage / 次数 | 输入中位 | 缓存输入中位 | 未缓存输入中位 | 输出中位 | 总 token / 成功任务 |',
    '|---|---|---|---|---|---|---|---|---|');
  const tokenLine = (client, task, group, subset) => {
    const tokens = subset.map(row => row.tokens ?? tokenUsage(client, row.usage)).filter(Boolean);
    const metric = key => median(tokens.map(item => item[key]).filter(Number.isFinite)) ?? '—';
    const successes = subset.filter(row => row.oracle_pass).length;
    const totals = tokens.map(item => item.total).filter(Number.isFinite);
    const perSuccess = successes && totals.length === subset.length
      ? Math.round(totals.reduce((sum, count) => sum + count, 0) / successes) : '—';
    return `| ${client} | ${task} | ${group} | ${tokens.length}/${subset.length} | ${metric('input')} | ${metric('cached_input')} | ${metric('uncached_input')} | ${metric('output')} | ${perSuccess} |`;
  };
  for (const client of distinct('client')) for (const group of distinct('group')) {
    const subset = rows.filter(row => row.client === client && row.group === group);
    if (subset.length) lines.push(tokenLine(client, '全部', group, subset));
    for (const task of distinct('task')) {
      const selected = subset.filter(row => row.task === task);
      if (selected.length) lines.push(tokenLine(client, task, group, selected));
    }
  }
  lines.push('', '总 token / 成功任务计入有 usage 的失败和超时。任一会话的总 token 缺失时，该值留空。');
  const loads = rows.map(row => row.load1_at_start).filter(Number.isFinite).map(Math.round);
  lines.push('', `共 ${rows.length} 次有效会话；客户端没连上模型、不计入的 ${unreachable} 次。开始时一分钟负载 ${range(loads)}，中位 ${median(loads)}。`);
  const text = lines.join('\n') + '\n';
  await writeFile(join(out, 'report.md'), text);
  console.log(text);
}

async function prepare({ udids, fixture }) {
  const shims = await makeShims(join(here, '.runtime/eval-shims'));
  const { Client } = await import('@modelcontextprotocol/client');
  const { StdioClientTransport } = await import('@modelcontextprotocol/client/stdio');
  for (const udid of udids) {
    const stateDir = join(here, '.runtime/eval-prepare', udid);
    await mkdir(stateDir, { recursive: true, mode: 0o700 });
    const daemon = await startDaemon(here, stateDir, shims, udid);
    try {
      const client = new Client({ name: 'eval-prepare', version: '1' });
      await client.connect(new StdioClientTransport({ command: process.execPath, args: [join(here, 'src/stdio.mjs')], env: { ...process.env, POKI_MCP_STATE_DIR: stateDir } }));
      const started = await client.callTool({ name: 'start_simulator', arguments: { simulator: udid } }, { timeout: 300000 });
      if (started.isError) throw new Error(`start_simulator failed: ${JSON.stringify(started.content)}`);
      await client.close();
      await run('/usr/bin/xcrun', ['simctl', 'install', udid, fixture]);
      console.log(`${udid}: booted and fixture installed`);
    } finally { daemon.child.kill('SIGTERM'); await once(daemon.child, 'exit'); }
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { positionals: [command], values } = parseArgs({ allowPositionals: true, options: {
    udids: { type: 'string' }, out: { type: 'string' }, root: { type: 'string', multiple: true }, clients: { type: 'string', default: 'claude,codex' },
    tasks: { type: 'string', default: 'counter,form,wrong_target' }, repeat: { type: 'string', default: '5' }, fixture: { type: 'string' }, 'timeout-seconds': { type: 'string', default: '420' },
    fast: { type: 'string', multiple: true }, skill: { type: 'string', multiple: true }, keyboard: { type: 'string', default: 'zh_Hans-Pinyin' }, retries: { type: 'string', default: '3' },
  } });
  if (command === 'report') await report(values.out);
  else if (command === 'prepare') await prepare({ udids: values.udids.split(','), fixture: values.fixture });
  else if (command === 'run') {
    const roots = Object.fromEntries(values.root.map(pair => pair.split('=')));
    const fastEntry = Object.fromEntries((values.fast ?? []).map(pair => pair.split('=')));
    const groups = Object.keys(roots), specs = values.udids.split(','), out = resolve(values.out);
    await mkdir(out, { recursive: true });
    const shims = await makeShims(join(out, 'shims'));
    const simulators = Object.values(JSON.parse((await run('/usr/bin/xcrun', ['simctl', 'list', 'devices', '--json'])).stdout).devices).flat();
    const lanes = await Promise.all(specs.map(async (spec, index) => {
      const devices = spec.split('+');
      const daemons = {};
      for (const group of groups) {
        const stateDir = join(out, 'state', `lane${index + 1}-${group}`);
        await mkdir(stateDir, { recursive: true, mode: 0o700 });
        daemons[group] = await startDaemon(resolve(roots[group]), stateDir, shims, devices.join(','));
      }
      return { udid: devices[0], devices, names: devices.map(udid => simulators.find(device => device.udid === udid).name), daemons };
    }));
    for (const task of values.tasks.split(',')) if ((tasks[task].devices ?? 1) > Math.min(...lanes.map(lane => lane.devices.length))) throw new Error(`${task} needs a lane of ${tasks[task].devices} simulators, written A+B.`);
    const done = new Set((await readFile(join(out, 'results.jsonl'), 'utf8').catch(() => '')).trim().split('\n').filter(Boolean).map(line => JSON.parse(line).id));
    const queue = schedule({ groups, clients: values.clients.split(','), taskNames: values.tasks.split(','), repeat: Number(values.repeat), fastEntry }).filter(job => !done.has(job.id));
    console.log(`${queue.length} sessions over ${lanes.length} simulators`);
    const skills = Object.fromEntries((values.skill ?? []).map(pair => { const [group, path] = pair.split('='); return [group, resolve(path)]; }));
    const options = { out, skills, timeoutMs: Number(values['timeout-seconds']) * 1000, keyboard: values.keyboard };
    const attempts = new Map();
    try {
      await Promise.all(lanes.map(async lane => {
        for (let job = queue.shift(); job; job = queue.shift()) {
          try {
            const tries = (attempts.get(job.id) ?? 0) + 1;
            attempts.set(job.id, tries);
            const result = await runJob(job, lane, { ...options, attempt: tries });
            // A session whose client never reached its model says nothing about the tools.
            if (result.client_unreachable && tries < Number(values.retries)) queue.push(job);
          }
          catch (error) { console.log(`${job.id}: rig error ${error.message}`); await appendFile(join(out, 'rig-errors.log'), `${job.id}: ${error.stack}\n`); }
        }
      }));
    } finally {
      for (const lane of lanes) for (const daemon of Object.values(lane.daemons)) daemon.child.kill('SIGTERM');
    }
    await report(out);
  } else throw new Error('Use prepare, run or report.');
}
