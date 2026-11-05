// Source: poki-app gateway/fast/session.mjs at 9972d34.
// Source: poki-mcp/client/fast/session.mjs. App owns the MCP connection and cancellation.
export class FastSession {
  constructor(call, stats, signal) {
    this.invoke = call;
    this.stats = stats;
    this.signal = signal;
  }
  async call(name, args, cleanup = false) {
    const started = performance.now();
    try {
      if (!cleanup) this.signal.throwIfAborted();
      const result = await this.invoke(name, args);
      if (result.isError) throw new Error(name === 'acquire_device' ? 'device_unavailable' : 'tool_failed');
      const blocks = result.content.filter(b => b.type === 'text');
      if (blocks.length !== 1) throw new Error('tool_protocol');
      const value = JSON.parse(blocks[0].text);
      if (!value || typeof value !== 'object' || value.isError || value.stopped && name !== 'release_device' || value.outcome === 'unknown') throw new Error('unknown_outcome');
      return value;
    } finally {
      this.stats.tool_calls++;
      const elapsed = performance.now() - started;
      this.stats.tool_ms += elapsed;
      if (name === 'get_foreground_app' || name === 'launch_app') this.stats.scope_ms += elapsed;
    }
  }
  async close(leaseId) {
    if (!leaseId) return true;
    try { await this.call('release_device', { lease_id: leaseId }, true); return true; }
    catch { return false; }
  }
}
