import { parentPort, workerData } from 'node:worker_threads';
import vm from 'node:vm';

// Runs one normalized async arrow function in a fresh vm context. The context has no require,
// process, fetch, module loader or timers: only JavaScript intrinsics, plus a `tools` proxy, an
// `input` value and a `console` shim built inside the context. Each `await tools.<name>(args)`
// crosses to the daemon as a JSON string and comes back as a JSON string, so no main-thread object
// ever reaches the context. The daemon drives the call and can terminate this worker at any time.
const { code, inputJson } = workerData;
const pending = new Map();
let nextId = 0;

// Worker-realm primitives placed on the context global. The context reaches the daemon only through
// these, and only with strings and numbers.
function dispatch(name, argsJson) {
  const id = nextId++;
  return new Promise(resolve => {
    pending.set(id, resolve);
    parentPort.postMessage({ type: 'call', id, name, argsJson });
  });
}
function emitLog(line) { parentPort.postMessage({ type: 'log', line }); }

parentPort.on('message', message => {
  if (message.type !== 'result') return;
  const resolve = pending.get(message.id);
  if (!resolve) return;
  pending.delete(message.id);
  resolve(message.resultJson);
});

const sandbox = { __dispatch: dispatch, __emitLog: emitLog, __inputJson: inputJson ?? 'null' };
const context = vm.createContext(sandbox, { codeGeneration: { strings: false, wasm: false } });

// Built inside the context so `tools`, `input` and `console` are context-realm objects. A tool call
// stringifies its argument, hands the daemon a plain string, parses the reply back into a
// context-realm object, and throws an ordinary Error the script can catch when the reply carries one.
const prelude = `
  globalThis.input = JSON.parse(__inputJson);
  globalThis.console = {
    log: (...a) => __emitLog(a.map(String).join(' ')),
    warn: (...a) => __emitLog('[warn] ' + a.map(String).join(' ')),
    error: (...a) => __emitLog('[error] ' + a.map(String).join(' ')),
    info: (...a) => __emitLog(a.map(String).join(' ')),
    debug: (...a) => __emitLog(a.map(String).join(' ')),
  };
  globalThis.tools = new Proxy({}, {
    get: (_, name) => {
      if (typeof name !== 'string') return undefined;
      return async (args) => {
        const replyJson = await __dispatch(name, JSON.stringify(args ?? {}));
        const reply = JSON.parse(replyJson);
        if (reply.error) throw new Error(reply.error);
        return reply.result;
      };
    },
  });
`;

async function run() {
  new vm.Script(prelude).runInContext(context);
  const fn = new vm.Script(`(${code})`).runInContext(context);
  const result = await fn();
  // The return value re-enters the daemon as a string, so a context-realm object never crosses back.
  return JSON.stringify(result ?? null);
}

run().then(
  resultJson => parentPort.postMessage({ type: 'done', resultJson }),
  error => parentPort.postMessage({ type: 'done', error: error instanceof Error ? error.message : String(error) }),
);
