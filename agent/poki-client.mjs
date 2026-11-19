import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';
import { fileURLToPath } from 'node:url';
import { connectLocalMCP } from '../src/local-mcp-client.mjs';

export class PokiClient {
  async open(session) {
    const direct = await connectLocalMCP({ name: 'poki-agent', version: '0.1.1', session,
      toolProfile: process.env.POKI_TOOL_PROFILE === 'cua' ? 'cua' : 'default' });
    // Older daemons expose the complete catalog through the stdio bridge.
    if (!direct) return this.openStdio(session);
    try {
      const { tools } = await direct.listTools();
      this.direct = direct;
      this.instructions = direct.instructions;
      return tools;
    } catch (error) {
      await direct.close();
      throw error;
    }
  }

  async openStdio(session) {
    this.client = new Client({ name: 'poki-agent', version: '0.1.1' });
    await this.client.connect(new StdioClientTransport({
      command: process.execPath,
      args: [fileURLToPath(new URL('../src/stdio.mjs', import.meta.url))],
      env: { ...process.env, POKI_MCP_SESSION: session, POKI_MCP_TOOLS: 'all' },
      stderr: 'ignore',
    }));
    this.instructions = this.client.getInstructions() ?? '';
    return (await this.client.listTools()).tools;
  }

  call(name, args = {}) {
    if (process.connected && name !== 'poki_mcp_status') process.send({ type: 'poki-device-call', name });
    // Just above the daemon's own 120 s remote cap, so a slow link fails there with a real report
    // instead of being cut off here with a bare "Request timed out".
    const configured = Number(process.env.POKI_MCP_CALL_TIMEOUT_MS);
    const timeout = Number.isFinite(configured) && configured > 0 ? configured : 130000;
    if (this.direct) return this.direct.callTool(name, args, { timeout }).catch(error => {
      if (error.code === 'REQUEST_TIMEOUT') throw error;
      return { isError: true, content: [{ type: 'text', text: error.message }] };
    });
    return this.client.callTool({ name, arguments: args }, { timeout });
  }

  async close() { await (this.direct ?? this.client)?.close(); }
}
