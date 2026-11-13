import { StdioServerTransport } from '@modelcontextprotocol/server/stdio';
import { createServer } from './tools.mjs';
import { connectLocalMCP } from './local-mcp-client.mjs';
import { version } from './build-info.mjs';

const remote = await connectLocalMCP({ name: 'poki-mcp-bridge', version, session: process.env.POKI_MCP_SESSION });
const server = createServer((name, args, extra) => remote.callTool(name, args, { signal: extra.signal, timeout: 3700000 }));
const transport = new StdioServerTransport();
await server.connect(transport);
let stopping;
function stop() {
  return stopping ??= (async () => {
    await remote.close();
    await server.close();
  })();
}
process.stdin.once('end', () => { void stop(); });
process.on('SIGINT', () => { void stop(); });
process.on('SIGTERM', () => { void stop(); });
