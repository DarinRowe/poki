import { registerHooks } from 'node:module';
const replacement = `
  import { appendFileSync } from 'node:fs';
  export class PokiClient {
    async open() { return [{ name: 'observe_device' }]; }
    async close() {}
    async call(name) {
      appendFileSync(process.env.POKI_TEST_DEVICE_CALLS, name + '\\n');
      throw new Error('Device calls are forbidden in this idle supervisor test.');
    }
  }
`;
registerHooks({ load(url, context, nextLoad) {
  if (url.endsWith('/agent/poki-client.mjs')) return { format: 'module', source: replacement, shortCircuit: true };
  return nextLoad(url, context);
} });
