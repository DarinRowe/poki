import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const resolveStateDir = () => process.env.POKI_MCP_STATE_DIR
  ?? join(homedir(), 'Library/Application Support/PokiMCP');
export const stateDir = resolveStateDir();
export const endpointFile = join(stateDir, 'mcp.json');
// usbmuxd answered with an empty list. Finder uses the same macOS device stack, so it is the first check.
export const noUsbDevice = 'usbmuxd answered, but no iPhone is attached over USB. Check whether the iPhone appears in the Finder sidebar. If Finder does not show it either, macOS has not attached it: connect it directly with a data cable, unlock it, and accept Trust This Computer. Poki cannot use an iPhone that devicectl reaches only over the network.';
export const idevice = process.env.IDEVICE_TOOLS
  ?? join(root, '.deps/idevice/target/release/idevice-tools');
