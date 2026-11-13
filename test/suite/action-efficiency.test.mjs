import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, appendFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createInterface } from 'node:readline';
import { join } from 'node:path';
import sharp from 'sharp';
import { fixture, value } from '../fixture.mjs';
import { tokenUsage, pairedText, overlapRounds, toolWallTime } from '../../bin/eval-first-call.mjs';
import { startResourceSampling } from './resource-sampling.mjs';

const root = { role: 'Application', frame: { x: 0, y: 0, width: 100, height: 200 } };
const element = (label, y, role = 'Button', extra = {}) => ({
  role, label, object_id: 'fixture-' + y, enabled: true,
  frame: { x: 20, y, width: 40, height: 20 }, ...extra,
});
const text = (label, y) => element(label, y, 'StaticText');
const screen = (...elements) => [root, ...elements];
const tap = (y, effect, elements, options) => ({
  op: 'tap', args: { x: Math.round(40 / 99 * 65535), y: Math.round((y + 10) / 199 * 65535) },
  effect, state: { elements }, ...options,
});
const textField = (label, y, value, focused = false) => element(label, y, 'TextField', { value, focused });
const initial = (elements, evalActions, extra) => ({ launched: true, elements, evalActions, ...extra });

function cases(word, variant = false) {
  const increment = element('Increment', 35), count = n => text('Count: ' + n, 70);
  const open = element('Open Detail', 35), back = element('Return to list', 80);
  const detail = screen(back, text('Detail ready', 120));
  const list = screen(open, text('List ready', 110));
  const row = element(variant ? 'Record 72' : 'Row 250', 130);
  const dismiss = element(variant ? 'Continue browsing' : 'Not now', 50);
  const rowSelected = row.label + ' selected';
  const interrupted = screen({ ...element(variant ? 'Session notice' : 'Just a moment', 25), role: variant ? 'Sheet' : 'Alert' }, dismiss, row);
  const visualTarget = variant ? 'Route badge' : 'Canvas target';
  const visualDecoy = variant ? 'Route badge legend' : 'Canvas area';
  const visualResult = variant ? 'Route opened' : 'Canvas tapped';
  const field = (value, focused) => textField('Destination', 70, value, focused);
  const neighbor = textField('Neighbor', 105, 'keep');
  const start = element('Start editing', 30), save = element('Save', 145);
  const saved = screen(field(word, false), neighbor, text('Saved once', 175));
  return {
    reference: {
      goal: 'On the current screen, click Increment exactly once and report the resulting count.',
      setup: initial(screen(increment, count(0)), [tap(35, 'increment', screen(increment, count(1)))]),
      run: async ui => ui.tap('Increment', 'Count: 1'),
      effects: ['increment'], finish: 'Count: 1',
    },
    navigation: {
      goal: 'Open Detail, wait until Return to list is available, then use it to go back. Report the final page.',
      setup: initial(list, [tap(35, 'open', detail, { reads: 2 }), tap(80, 'return', list)]),
      run: async ui => { await ui.tap('Open Detail', 'Return to list'); await ui.tap('Return to list', 'List ready'); },
      effects: ['open','return'], finish: 'List ready',
    },
    recovery: {
      goal: 'Click Increment twice to reach Count: 2. The second attempt may lose its receipt; check the count before taking any further action. Once the count is 2, click Open Detail exactly once and report the destination.',
      setup: initial(screen(increment, count(0), element('Open Detail', 95)), [
        tap(35,'increment',screen(increment,count(1),element('Open Detail',95))),
        tap(35,'increment',screen(increment,count(2),element('Open Detail',95)), {
          reply:{isError:true,outcome:'unknown',stop_reason:'unknown'},
        }), tap(95,'open',detail),
      ]),
      run: async ui => {
        await ui.tap('Increment','Count: 1');
        await ui.tap('Increment','Count: 2',true);
        assert.ok((await ui.look()).elements.some(e=>e.label==='Count: 2'));
        await ui.tap('Open Detail','Detail ready');
      },
      effects:['increment','increment','open'],finish:'Detail ready',
    },
    interruption: {
      goal:`Swipe up to find ${row.label}. If a modal appears, dismiss it via ${dismiss.label} before clicking ${row.label} exactly once. Report the resulting state.`,
      setup:initial(screen(text(variant ? 'Record 1' : 'Row 1',35)),[
        {op:'drag',effect:'scroll',state:{elements:interrupted},...(variant ? {reads:2} : {})},
        tap(50,'dismiss',screen(row)),tap(130,'row',screen(text(rowSelected,90))),
      ]),
      run:async ui=>{
        await ui.call('swipe',{from_x:50,from_y:160,to_x:50,to_y:50});
        await ui.call('handle_alert',{button:dismiss.label});
        await ui.tap(row.label,rowSelected);
      },
      effects:['scroll','dismiss','row'],finish:rowSelected,
    },
    focus: {
      goal:`Click Start editing and wait for Destination to gain focus. Enter "${word}" in Destination and preserve Neighbor. Click Save once and report the saved state.`,
      setup:initial(screen(start,field('',false),neighbor,save),[
        tap(30,'focus',screen(start,field('',true),neighbor,save),{reads:3}),
        {op:'type_text',args:{text:word,submit:false},effect:'fill',state:{elements:screen(field(word,true),neighbor,save)}},
        tap(145,'save',saved),
      ]),
      run:async ui=>{
        await ui.tap('Start editing','Destination',false,'focused');
        await ui.call('fill',{field:'Destination',text:word,submit:false});
        await ui.tap('Save','Saved once');
      },
      effects:['focus','fill','save'],finish:'Saved once',
      check:state=>assert.deepEqual(state.elements.filter(e=>e.role==='TextField').map(e=>e.value),[word,'keep']),
    },
    canvas: {
      goal:`Click the control labeled "${visualTarget}". Its text is visible in the screenshot. Report the resulting state.`,
      setup:initial(screen(text(visualDecoy,135)),[
        {op:'tap',bounds:{x:[0.1,0.9].map(fraction=>Math.round(fraction*65535)),y:[75,95].map(y=>Math.round(y/199*65535))},
          effect:'canvas',state:{elements:screen(text(visualResult,145)),ocrElements:[]}},
      ],{ocrElements:[{text:visualTarget,x:10,y:75,width:80,height:20}]}),
      async prepare(f) {
        const render = (path, label, y, other = '') => sharp(Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="100" height="200"><rect width="100" height="200" fill="white"/><rect x="10" y="${y}" width="80" height="20" rx="3" fill="#dbeafe"/><g text-anchor="middle" font-family="sans-serif" font-size="9"><text x="50" y="${y+13}">${label}</text><text x="50" y="148">${other}</text></g></svg>`)).png().toFile(path);
        const before=join(f.dir,'canvas-before.png'), after=join(f.dir,'canvas-after.png');
        await Promise.all([render(before,visualTarget,75,visualDecoy),render(after,visualResult,145)]);
        this.setup.screenshot=before;
        this.setup.evalActions[0].state.screenshot=after;
      },
      run:async ui=>{ await ui.look(); await ui.call('tap_text',{text:visualTarget,exact:true}); },
      effects:['canvas'],finish:visualResult,
    },
  };
}

function oracle(state, scenario) {
  const events = state.evalEvents ?? [];
  assert.deepEqual(events.map(event=>event.effect),scenario.effects);
  assert.ok(events.every(event=>event.match));
  assert.ok(state.elements.some(element=>element.label===scenario.finish));
  scenario.check?.(state);
}

function callEvidence(result) {
  const blocks = (result?.content ?? []).flatMap(block => {
    if (block.type !== 'text') return [];
    try { return [JSON.parse(block.text)]; } catch { return []; }
  }).filter(block => block && typeof block === 'object');
  return {
    direct_hits: blocks.filter(block => block.target_source === 'validated_reference').length,
    matched_conditions: blocks.filter(block => block.expectation?.matched === true).length,
    refusals: blocks.flatMap(block => typeof block.reason === 'string' && block.outcome === 'not_sent' ? [block.reason] : []),
  };
}

async function scripted(f, after, scenario, calls) {
  const call = async (name,args={},error=false) => {
    const startedAt=performance.now();
    const result=await f.call(name,args);
    calls.push({name,startedAt,endedAt:performance.now(),error:!!result.isError,stages:result._meta?.timing?.stages ?? [],...callEvidence(result)});
    assert.equal(!!result.isError,error,JSON.stringify(result.content));
    return value(result);
  };
  const look=()=>call('observe_device',{fallback:'hybrid'});
  const tap=async (label,expect,error=false,state='visible')=>{
    const observed=await look();
    const target=observed.elements.find(e=>e.label===label);
    assert.ok(target,label);
    const result=await call('tap',{ref:target.ref,return_observation:true,...(after?{expect:{text:expect,state}}:{})},error);
    if (!error && after) {
      assert.equal(result.target_source,'validated_reference');
      assert.equal(result.expectation?.matched,true);
    }
  };
  await scenario.run({call,look,tap});
}

async function withModel(f, after, scenario, calls) {
  const config = ['-c','mcp_servers.phone.command="node"','-c',
    `mcp_servers.phone.args=[${JSON.stringify(f.dir+'/src/stdio.mjs')}]`,'-c',
    `mcp_servers.phone.env={POKI_MCP_STATE_DIR=${JSON.stringify(f.dir+'/state')}}`];
  const guidance = after
    ? 'For a known newly appearing exact AX label, pass expect={text,state} on tap or tap_text. Use AX refs from observe_device fallback=hybrid. Never repeat an uncertain action before verifying its effect.'
    : 'Use AX refs from observe_device fallback=hybrid and ordinary tap readback. Never repeat an uncertain action before verifying its effect.';
  const prompt = 'This is an isolated synthetic phone fixture. Use only the phone MCP tools. Do not use shell, files, network, other devices or external tools. '+scenario.goal+' '+guidance+' The final answer must include the exact verified on-screen state label.';
  const child = spawn('codex',['exec','--ignore-user-config','--skip-git-repo-check','--ephemeral',
    '--dangerously-bypass-approvals-and-sandbox','-c','features.shell_tool=false','-c','web_search="disabled"','--json','-C',f.dir,'-m',process.env.POKI_EVAL_MODEL,...config,prompt],
    {stdio:['ignore','pipe','ignore']});
  const closed=once(child,'close');
  const timer=setTimeout(()=>child.kill('SIGKILL'),150000);
  let usage, reply='';
  const startedCalls=new Map();
  try {
    for await (const line of createInterface({input:child.stdout})) {
      let event;
      try { event=JSON.parse(line); } catch { continue; }
      if (event.type==='turn.completed') usage=event.usage;
      const item=event.item;
      if (event.type==='item.started' && item?.type==='mcp_tool_call') startedCalls.set(item.id,performance.now());
      if (event.type==='item.completed' && item?.type==='agent_message') reply=item.text;
      if (event.type==='item.completed' && item?.type==='mcp_tool_call') {
        const args=item.arguments ?? {};
        const target=Object.fromEntries(['text','ref','x','y','verify','exact','ax_hint','skip_ax','require_visual'].filter(key=>key in args).map(key=>[key,args[key]]));
        calls.push({name:item.tool,target,startedAt:startedCalls.get(item.id),endedAt:performance.now(),
          error:item.status==='failed'||!!item.error,stages:item.result?._meta?.timing?.stages??[],...callEvidence(item.result)});
      }
    }
    const [status]=await closed;
    return {tokens:tokenUsage('codex',usage),model_rounds_estimate:overlapRounds(calls)+1,
      client_exit:status, reply_verified:reply.toLowerCase().includes(scenario.finish.toLowerCase())};
  } finally {clearTimeout(timer);}
}

const suite=process.env.POKI_EVAL_GROUP ?? 'all';
assert.ok(['all','development','holdout'].includes(suite));
const model=Boolean(process.env.POKI_EVAL_MODEL);
const repeat=Number(process.env.POKI_EVAL_REPEAT ?? 1);
assert.ok(Number.isSafeInteger(repeat)&&repeat>0);
const names=Object.keys(cases('fixture'));
const selected=process.env.POKI_EVAL_SCENARIO?.split(',');
assert.ok(!selected||selected.every(name=>names.includes(name)));
const beforeRoot=process.env.POKI_EVAL_BEFORE_ROOT;
const variant=process.env.POKI_EVAL_VARIANT==='1';
const sampleResources=process.env.POKI_EVAL_RESOURCES==='1';
for (let round=1;round<=repeat;round++) for (const [index,name] of names.entries()) {
  const group=index<3?'development':'holdout';
  if(suite!=='all'&&group!==suite||selected&&!selected.includes(name))continue;
  for(const after of round%2 ? [false,true] : [true,false]) test(`${group} ${name} ${after?'after':'before'} ${round}`,{timeout:180000},async t=>{
    const optimized=after||Boolean(beforeRoot);
    const flag=optimized?'1':'0';
    const f=await fixture(t,{...(!after&&beforeRoot?{sourceRoot:beforeRoot}:{}),
      extraEnv:()=>({POKI_DIRECT_REF:flag,POKI_CONDITIONAL_WAIT:flag})});
    const scenario=cases(pairedText({task:name,client:model?'codex':'script',round}),variant)[name];
    await scenario.prepare?.(f);
    await f.set(scenario.setup);
    const calls=[];
    const finishSampling=sampleResources ? await startResourceSampling(f.daemon.pid) : undefined;
    const started=performance.now();
    let error, metrics, elapsed, resources;
    try {
      try {
        metrics=model?await withModel(f,optimized,scenario,calls):await scripted(f,optimized,scenario,calls);
      } finally {
        elapsed=Math.round(performance.now()-started);
        resources=await finishSampling?.(elapsed);
      }
      const state=JSON.parse(await readFile(f.env.FIXTURE_STATE,'utf8'));
      oracle(state,scenario);
      if (model) {
        assert.equal(metrics.client_exit,0,'Codex process failed');
        assert.equal(metrics.reply_verified,true,'Final answer did not report the verified screen state');
      }
    } catch (cause) {error=cause;}
    const state=JSON.parse(await readFile(f.env.FIXTURE_STATE,'utf8'));
    const phases=calls.flatMap(call=>call.stages);
    const row={group,name,after,round,variant,model:model?process.env.POKI_EVAL_MODEL:null,passed:!error,
      elapsed_ms:elapsed,tool_calls:calls.length,tool_wall_ms:toolWallTime(calls),call_details:calls,
      explicit_reads:calls.filter(call=>['observe_device','list_elements','take_screenshot','wait_for'].includes(call.name)).length,
      ax_reads:phases.filter(stage=>stage.phase==='accessibility').length,
      captures:phases.filter(stage=>stage.phase==='screen_capture').length,
      direct_hits:calls.reduce((total,call)=>total+call.direct_hits,0),
      matched_conditions:calls.reduce((total,call)=>total+call.matched_conditions,0),
      refusals:calls.flatMap(call=>call.refusals),
      observed_actions:(state.evalEvents??[]).map(({key,...event})=>event.match ? event : { ...event, request:JSON.parse(key) }),
      repeated_actions:(state.evalEvents??[]).filter(event=>event.repeated).length,wrong_actions:(state.evalEvents??[]).filter(event=>!event.match).length,
      ...metrics,...(resources?{resources}:{}),...(error?{error:error.message}:{})};
    if(process.env.POKI_EVAL_RESULTS) await appendFile(process.env.POKI_EVAL_RESULTS,JSON.stringify(row)+'\n',{mode:0o600});
    if(error)throw error;
  });
}
