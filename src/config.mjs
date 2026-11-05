import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const stateDir = process.env.POKI_MCP_STATE_DIR
  ?? join(homedir(), 'Library/Application Support/PokiMCP');
export const endpointFile = join(stateDir, 'mcp.json');
export const idevice = process.env.IDEVICE_TOOLS
  ?? join(root, '.deps/idevice/target/release/idevice-tools');
