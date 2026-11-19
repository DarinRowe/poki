import { readFile } from 'node:fs/promises';

const paths = process.argv.slice(2);
if (!paths.length) throw Error('Usage: node test/suite/report-action-efficiency.mjs <results.jsonl> [...]');
const rows = (await Promise.all(paths.map(path => readFile(path, 'utf8'))))
  .flatMap(content => content.trim().split('\n').filter(Boolean).map(line => JSON.parse(line)));

const sum = values => values.reduce((total, value) => total + value, 0);
const median = values => {
  const sorted = values.filter(Number.isFinite).sort((a,b)=>a-b);
  if (!sorted.length) return null;
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};
const p95 = values => [...values].sort((a,b)=>a-b)[Math.ceil(values.length * .95)-1];
const secs = value => Number.isFinite(value) ? (value / 1000).toFixed(3) : '—';
const number = value => Number.isFinite(value) ? String(Math.round(value)) : '—';
const decimal = value => Number.isFinite(value) ? value.toFixed(1) : '—';
const split = (values, key) => [...new Set(values.map(key))];
const phase = (row, name) => {
  const stages = (row.call_details ?? []).flatMap(call => call.stages ?? []).filter(stage => stage.phase === name);
  return stages.length ? sum(stages.map(stage => stage.elapsed_ms)) : null;
};

for (const model of split(rows, row=>row.model ?? 'script')) {
  const trials=rows.filter(row=>(row.model??'script')===model);
  const pairs=new Map();
  for (const trial of trials) {
    const key=JSON.stringify([trial.group,trial.name,Boolean(trial.variant),trial.round]);
    const pair=pairs.get(key)??{};
    const arm=trial.after?'after':'before';
    if (pair[arm]) throw Error('Duplicate trial '+key+' '+arm);
    pair[arm]=trial;
    pairs.set(key,pair);
  }
  console.log(`\n## ${model}\n\n| 场景 | 组 | 成功 / 总数 | 误动作尝试 | 重做已完成动作尝试 | 总耗时秒 | 中位秒 | P95 秒 | 调用 | 显式读屏 | AX | 截图 |\n|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|`);
  const emit = (label, data, after) => {
    const group=data.filter(row=>row.after===after);
    if (!group.length) return;
    const passed=group.filter(row=>row.passed).length;
    const times=group.map(row=>row.elapsed_ms);
    const total=key=>sum(group.map(row=>row[key]??0));
    console.log(`| ${label} | ${after?'新版':'旧版'} | ${passed}/${group.length} | ${total('wrong_actions')} | ${total('repeated_actions')} | ${secs(sum(times))} | ${secs(median(times))} | ${secs(p95(times))} | ${total('tool_calls')} | ${total('explicit_reads')} | ${total('ax_reads')} | ${total('captures')} |`);
  };
  for (const after of [false,true]) emit('全部',trials,after);
  for (const name of split(trials,row=>row.name)) for (const after of [false,true]) emit(name,trials.filter(row=>row.name===name),after);

  for (const after of [false,true]) {
    const group=trials.filter(row=>row.after===after);
    if (!group.length || group.some(row=>!Number.isFinite(row.direct_hits))) continue;
    const rejected=group.flatMap(row=>row.refusals??[]);
    const reasons=Object.fromEntries(split(rejected, reason=>reason).map(reason=>[reason,rejected.filter(value=>value===reason).length]));
    console.log(`\n${after?'新版':'旧版'}已核验引用命中 ${sum(group.map(row=>row.direct_hits))}，条件满足 ${sum(group.map(row=>row.matched_conditions))}，明确拒绝 ${JSON.stringify(reasons)}。`);
  }
  const complete=[...pairs.values()].filter(pair=>pair.before&&pair.after);
  const bothPassed=complete.filter(pair=>pair.before.passed&&pair.after.passed);
  console.log(`\n双侧成功的配对 ${bothPassed.length}/${complete.length}。新减旧的配对耗时中位 ${secs(median(bothPassed.map(pair=>pair.after.elapsed_ms-pair.before.elapsed_ms)))} 秒。P95 是各组的样本分位。\n`);

  console.log('| 组 | 工具区间中位秒 | 其余耗时中位秒 | 动作前 AX 中位秒 | 定位与发送阶段中位秒 | 原生发送中位秒 | 条件等待中位秒 |');
  console.log('|---|---:|---:|---:|---:|---:|---:|');
  for (const after of [false,true]) {
    const group=trials.filter(row=>row.after===after);
    if(!group.length)continue;
    const middle=name=>secs(median(group.map(row=>phase(row,name))));
    console.log(`| ${after?'新版':'旧版'} | ${secs(median(group.map(row=>row.tool_wall_ms)))} | ${secs(median(group.map(row=>row.elapsed_ms-row.tool_wall_ms)))} | ${middle('pre_action_ax')} | ${middle('resolve_and_dispatch')} | ${middle('input')} | ${middle('postcondition_wait')} |`);
  }
  console.log('\n工具时间合并了重叠调用。其余耗时包含客户端、模型、启动和传输。阶段列可能嵌套。');
  if (trials.some(row=>row.resources)) {
    console.log('\n| 场景 | 组 | 有进程采样 / 次数 | 空闲 RSS MiB | 峰值 RSS MiB | CPU ms | 平均 CPU % 单核 | 有 GPU 采样 / 次数 | 整机平均 GPU % | 整机峰值 GPU % |');
    console.log('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|');
    for (const name of [null,...split(trials,row=>row.name)]) for (const after of [false,true]) {
      const group=trials.filter(row=>row.after===after&&(!name||row.name===name));
      if (!group.length) continue;
      const resourceRows=group.map(row=>row.resources).filter(Boolean);
      const middle=key=>decimal(median(resourceRows.map(row=>row[key])));
      console.log(`| ${name??'全部'} | ${after?'新版':'旧版'} | ${resourceRows.filter(row=>row.samples>0).length}/${group.length} | ${middle('idle_rss_mib')} | ${middle('peak_rss_mib')} | ${middle('cpu_ms_observed')} | ${middle('cpu_mean_pct_one_core_observed')} | ${resourceRows.filter(row=>row.host_gpu_samples>0).length}/${group.length} | ${middle('host_gpu_mean_pct')} | ${middle('host_gpu_peak_pct')} |`);
    }
    console.log('\n各数值为每次任务统计的组内中位数。CPU、RSS 取样覆盖 Poki 服务及其子进程，短命进程可能漏采。GPU 为 macOS 整机读数，包含其他进程活动。');
  }
  if(model==='script')continue;
  console.log('\n| 组 | 有 usage / 次数 | 输入中位 | 缓存中位 | 未缓存中位 | 输出中位 | 模型轮数估计中位 | 总 token / 成功任务 |\n|---|---:|---:|---:|---:|---:|---:|---:|');
  for(const after of [false,true]){
    const group=trials.filter(row=>row.after===after);
    if(!group.length)continue;
    const tokens=group.map(row=>row.tokens).filter(Boolean);
    const successes=group.filter(row=>row.passed).length;
    const middle=key=>number(median(tokens.map(row=>row[key])));
    const perSuccess=successes&&tokens.length===group.length&&tokens.every(row=>Number.isFinite(row.total))
      ? number(sum(tokens.map(row=>row.total))/successes) : '—';
    console.log(`| ${after?'新版':'旧版'} | ${tokens.length}/${group.length} | ${middle('input')} | ${middle('cached_input')} | ${middle('uncached_input')} | ${middle('output')} | ${number(median(group.map(row=>row.model_rounds_estimate)))} | ${perSuccess} |`);
  }
}
