import { readFile } from 'node:fs/promises';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { resolveStateDir } from './config.mjs';

const notRunning = () => new Error('Local Poki MCP is not running. Run npm start in its project first.');
const readEndpoint = async endpointFile => {
  const entry = await readFile(endpointFile, 'utf8').then(JSON.parse).catch(() => { throw notRunning(); });
  const url = new URL(entry.url);
  if (!entry.enabled || url.hostname !== '127.0.0.1' || url.protocol !== 'http:' || url.pathname !== '/mcp') throw new Error('Invalid local MCP endpoint');
  return { url, token: entry.token, agentToolProfiles: entry.agent_tool_profiles === true };
};
export async function connectLocalMCP({ name, version, session = randomUUID(), toolProfile }) {
  const endpointFile = join(resolveStateDir(), 'mcp.json');
  let endpoint = await readEndpoint(endpointFile);
  if (toolProfile && !endpoint.agentToolProfiles) return null;
  const send = (path, init) => {
    const headers = new Headers(init?.headers);
    headers.set('Authorization', `Bearer ${endpoint.token}`);
    headers.set('x-poki-mcp-session', session);
    if (toolProfile && path === '/mcp') {
      headers.set('x-poki-agent-tool-profile', toolProfile);
      headers.set('x-poki-agent-pid', String(process.pid));
    }
    return fetch(new URL(path, endpoint.url), { ...init, headers });
  };
  const refused = error => error.cause?.code === 'ECONNREFUSED';
  const lost = error => error.name === 'TypeError' && error.cause ? new Error('The connection to Poki MCP was lost during this call. The device may already have acted, so look at the screen before retrying. If the service stopped, run npm start in its project.') : error;
  // A restarted service has a new token and may have a new port. A 401 or a refused connection means it
  // never ran the request, so sending it once more cannot repeat anything on the device. Any other lost
  // connection can, so that one is reported and not sent again.
  async function request(path, init) {
    try {
      const response = await send(path, init);
      if (response.status !== 401) return response;
      await response.body?.cancel();
    } catch (error) {
      if (!refused(error)) throw lost(error);
    }
    endpoint = await readEndpoint(endpointFile);
    let response;
    try { response = await send(path, init); }
    catch (error) { throw refused(error) ? notRunning() : lost(error); }
    if (response.status !== 401) return response;
    await response.body?.cancel();
    throw new Error(`The running Poki MCP rejected the token in ${endpointFile}. Restart it with npm start.`);
  }
  const controls = new Set();
  const control = (path, extra = {}) => {
    const result = request(path, { method: 'POST', headers: extra, signal: AbortSignal.timeout(35000) })
      .then(response => response.body?.cancel());
    controls.add(result);
    result.finally(() => controls.delete(result)).catch(() => {});
    return result;
  };
  const remote = new Client({ name, version });
  try {
    await remote.connect(new StreamableHTTPClientTransport(endpoint.url, { fetch: (input, init) => request(new URL(input).pathname, init) }));
  } catch (error) {
    await control('/session/close').catch(() => {});
    await remote.close();
    throw error;
  }

  let closing;
  return {
    instructions: remote.getInstructions() ?? '',
    listTools: () => remote.listTools(),
    async callTool(name, args, { signal, timeout }) {
      const id = randomUUID();
      let cancellation;
      const cancel = () => { cancellation ??= control('/request/cancel', { 'x-poki-request': id }).catch(() => {}); };
      signal?.addEventListener('abort', cancel, { once: true });
      try {
        signal?.throwIfAborted();
        return await remote.callTool({ name, arguments: args, _meta: { 'poki/request_id': id } }, { timeout, signal });
      } catch (error) {
        if (error.code === 'REQUEST_TIMEOUT') cancel();
        throw error;
      } finally { signal?.removeEventListener('abort', cancel); }
    },
    close() {
      return closing ??= (async () => {
        await control('/session/close').catch(() => {});
        await Promise.allSettled([...controls]);
        await remote.close();
      })();
    },
  };
}
