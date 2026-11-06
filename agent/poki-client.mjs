import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';
import { fileURLToPath } from 'node:url';

export class PokiClient {
  async open(session) {
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
    return this.client.callTool({ name, arguments: args }, { timeout: 30000 });
  }

  async close() { await this.client?.close(); }
}
