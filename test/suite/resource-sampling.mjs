import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);
const intervalMs = 250;
const read = async (program, args) => {
  try { return (await run(program, args, { timeout: 1500, maxBuffer: 4 * 1024 * 1024 })).stdout; }
  catch { return ''; }
};

function cpuSeconds(time) {
  const [days, clock] = time.includes('-') ? time.split('-') : ['0', time];
  return Number(days) * 86400 + clock.split(':').reduce((seconds, part) => seconds * 60 + Number(part), 0);
}

function processTree(output, root) {
  const byParent = new Map();
  const processes = new Map();
  for (const line of output.split('\n')) {
    const fields = line.match(/^\s*(\d+)\s+(\d+)\s+(\d+)\s+([\d:.\-]+)\s*$/);
    if (!fields) continue;
    const [, pid, parent, rss, time] = fields;
    processes.set(Number(pid), { rss: Number(rss), cpu: cpuSeconds(time) });
    if (!byParent.has(Number(parent))) byParent.set(Number(parent), []);
    byParent.get(Number(parent)).push(Number(pid));
  }
  if (!processes.has(root)) return null;
  const tree = new Map();
  const pending = [root];
  while (pending.length) {
    const pid = pending.pop();
    if (tree.has(pid)) continue;
    tree.set(pid, processes.get(pid));
    pending.push(...(byParent.get(pid) ?? []));
  }
  return tree;
}

export async function startResourceSampling(daemonPid) {
  const known = new Map();
  const gpu = [];
  let samples = 0, peakRss = 0, idleRss = null, cpu = 0, lastCpuAt = null;

  async function sample(baseline = false) {
    const at = performance.now();
    const [ps, ioreg] = await Promise.all([
      read('/bin/ps', ['-axo', 'pid=,ppid=,rss=,time=']),
      !baseline && process.platform === 'darwin' ? read('/usr/sbin/ioreg', ['-r', '-c', 'IOAccelerator', '-d', '1']) : '',
    ]);
    const tree = processTree(ps, daemonPid);
    if (tree) {
      let rss = 0;
      for (const [pid, proc] of tree) {
        rss += proc.rss;
        const previous = known.get(pid);
        if (!baseline && lastCpuAt !== null) cpu += previous === undefined ? proc.cpu : Math.max(0, proc.cpu - previous);
        known.set(pid, proc.cpu);
      }
      if (baseline) idleRss = rss;
      else { samples++; peakRss = Math.max(peakRss, rss); }
      lastCpuAt = at;
    }
    const values = [...ioreg.matchAll(/"Device Utilization %"\s*=\s*(\d+(?:\.\d+)?)/g)]
      .map(match => Number(match[1])).filter(value => value <= 100);
    if (values.length) gpu.push(Math.max(...values));
  }

  await sample(true);
  let pending;
  const timer = setInterval(() => {
    if (!pending) pending = sample().finally(() => { pending = undefined; });
  }, intervalMs);
  return async elapsedMs => {
    clearInterval(timer);
    await pending;
    await sample();
    return {
      scope: 'poki_daemon_tree', interval_ms: intervalMs, samples, host_gpu_samples: gpu.length,
      idle_rss_mib: idleRss === null ? null : idleRss / 1024,
      peak_rss_mib: samples ? peakRss / 1024 : null,
      cpu_ms_observed: idleRss !== null && samples ? Math.round(cpu * 1000) : null,
      cpu_mean_pct_one_core_observed: idleRss !== null && samples && elapsedMs > 0 ? cpu * 100000 / elapsedMs : null,
      host_gpu_mean_pct: gpu.length ? gpu.reduce((sum, value) => sum + value, 0) / gpu.length : null,
      host_gpu_peak_pct: gpu.length ? Math.max(...gpu) : null,
    };
  };
}
