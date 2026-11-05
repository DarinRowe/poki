import { EventEmitter } from 'node:events';
import { randomUUID } from 'node:crypto';
import { readFile, mkdir, appendFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { modelConfig, safeModelError } from './model-config.mjs';
import { AssistantMessageEventStream, InMemoryCredentialStore } from '@earendil-works/pi-ai';

export class PiSession extends EventEmitter {
  #pending = new Map();
  #closed = false;

  constructor(options = {}) {
    super();
    this.options = { ...options };
    this.evidenceDirectory = options.evidenceDirectory;
  }

  async open() {
    this.sdk = await import('@earendil-works/pi-coding-agent');
    this.config = modelConfig(this.options);
    this.serviceTier = this.config.serviceTier === 'fast' ? 'priority' : this.config.serviceTier;
    if (this.config.auth === 'api-key' && !process.env.OPENAI_API_KEY?.trim()) throw new Error('Set OPENAI_API_KEY in your environment, or choose POKI_AGENT_AUTH=chatgpt and sign in with poki login.');
    this.runtime = await this.sdk.ModelRuntime.create({ modelsPath: null, allowModelNetwork: false,
      ...(this.config.auth === 'api-key' ? { credentials: new InMemoryCredentialStore() } : { authPath: process.env.POKI_AGENT_AUTH_FILE }),
    });
    if (this.config.auth === 'api-key') {
      this.provider = 'openai';
      await this.runtime.setRuntimeApiKey(this.provider, process.env.OPENAI_API_KEY);
    } else {
      const credentials = await this.runtime.listCredentials();
      this.provider = ['openai', 'openai-codex'].find(provider => credentials.some(c => c.providerId === provider && c.type === 'oauth'));
      if (!this.provider) throw new Error('ChatGPT is not signed in. Run poki login and choose ChatGPT. Then run Poki Agent again.');
    }
    const originalStream = this.runtime.streamSimple.bind(this.runtime);
    this.runtime.streamSimple = (model, context, options) => {
      const output = new AssistantMessageEventStream();
      void (async () => {
        this.serviceTier = this.config.serviceTier === 'fast' ? 'priority' : this.config.serviceTier;
        for (;;) {
          const events = [];
          const headers = { ...options?.headers };
          // service_tier is carried in the provider payload; Fast uses the supported priority spelling.
          for await (const event of originalStream(model, context, { ...options, headers })) events.push(event);
          const failure = events.find(event => event.type === 'error');
          if (failure && !['default', 'auto', undefined].includes(this.serviceTier) && /service.?tier|ultrafast|priority|flex/i.test(failure.error.errorMessage ?? '') &&
              /not.support|not.allowed|not.available|not.eligible|invalid|unsupported|access|permission|entitl/i.test(failure.error.errorMessage ?? '')) {
            this.#warnTier('rejected');
            this.serviceTier = 'default';
            continue;
          }
          if (failure) failure.error.errorMessage = safeModelError(failure.error.errorMessage);
          for (const event of events) output.push(event);
          output.end();
          return;
        }
      })().catch(error => {
        const message = { role: 'assistant', content: [], api: model.api, provider: model.provider, model: model.id,
          usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
          stopReason: 'error', errorMessage: safeModelError(error), timestamp: Date.now() };
        output.push({ type: 'error', reason: 'error', error: message }); output.end();
      });
      return output;
    };
  }

  async request(method, params) {
    if (this.#closed) throw new Error('Model session is closed');
    if (method === 'thread/start') {
      const { createAgentSession, DefaultResourceLoader, SessionManager, SettingsManager, resolveCliModel } = this.sdk;
      const resolved = resolveCliModel({ cliProvider: this.provider, cliModel: this.config.model, modelRuntime: this.runtime });
      if (resolved.error || !resolved.model) throw new Error(resolved.error ?? 'Requested model is unavailable in pi');
      if (resolved.model.id !== this.config.model) throw new Error('pi resolved a different model. Task not started.');
      resolved.model = { ...resolved.model, compat: { ...resolved.model.compat, supportsMidConvoEffort: false } };
      if (this.config.baseUrl) resolved.model = { ...resolved.model, baseUrl: this.config.baseUrl };
      const settingsManager = SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } });
      const loader = new DefaultResourceLoader({
        cwd: process.cwd(), agentDir: this.evidenceDirectory ?? fileURLToPath(new URL('./.runtime/pi', import.meta.url)), settingsManager,
        noExtensions: true, disabledBuiltinExtensions: ['mcp'], noSkills: true,
        noPromptTemplates: true, noThemes: true, noContextFiles: true,
        systemPromptOverride: () => params.developerInstructions,
        appendSystemPromptOverride: () => [],
      });
      await loader.reload();
      const names = params.dynamicTools.map(tool => tool.name);
      const { session } = await createAgentSession({
        modelRuntime: this.runtime, model: resolved.model, thinkingLevel: 'low',
        noTools: 'builtin', tools: names,
        customTools: params.dynamicTools.map(tool => ({
          name: tool.name, label: tool.name, description: tool.description, parameters: tool.inputSchema,
          execute: (id, args) => new Promise((resolve, reject) => {
            if (this.#closed) return reject(new Error('Task stopped'));
            this.#pending.set(id, { resolve, reject });
            this.emit('message', { id, method: 'item/tool/call', params: { tool: tool.name, arguments: args } });
          }),
        })),
        resourceLoader: loader, sessionManager: SessionManager.inMemory(), settingsManager,
      });
      this.session = session;
      session.agent.toolExecution = 'sequential';
      session.agent.onProviderStreamEvent = async event => {
        if (/delta$/.test(event?.type ?? '') && event.delta) this.firstDelta ??= performance.now();
        if (event?.type !== 'response.completed') return;
        this.servedServiceTier = event.response?.service_tier ?? null;
        if (this.serviceTier && !['auto', 'default'].includes(this.serviceTier) && this.servedServiceTier === 'default') {
          this.#warnTier('served default');
        }
        if (this.evidenceDirectory) await appendFile(join(this.evidenceDirectory, 'responses.jsonl'), JSON.stringify({ index: this.responseIndex, id: event.response?.id, model: event.response?.model, service_tier: this.servedServiceTier, usage: event.response?.usage }) + '\n', { mode: 0o600 });
      };
      this.instructions = params.developerInstructions;
      session.agent.onPayload = async payload => {
        payload.instructions = this.instructions;
        if (this.serviceTier === undefined) delete payload.service_tier;
        else payload.service_tier = this.serviceTier;
        const actual = [...new Set([...(payload.tools ?? []), ...(payload.input ?? []).filter(item => item.type === 'additional_tools').flatMap(item => item.tools ?? [])].map(tool => tool.name))];
        if (actual.length !== names.length || actual.some(name => !names.includes(name))) throw new Error(`pi tools do not match Poki: expected=${names.join(',')} actual=${actual.join(',')}`);
        this.responseStarted = performance.now();
        this.requestedServiceTier = payload.service_tier ?? null;
        this.requestEffort = payload.reasoning?.effort ?? null;
        this.emit('request', { index: (this.responseIndex ?? 0) + 1, model: payload.model, effort: this.requestEffort, serviceTier: this.requestedServiceTier, at: new Date().toISOString() });
        this.firstDelta = null;
        this.servedServiceTier = null;
        this.responseIndex = (this.responseIndex ?? 0) + 1;
        if (this.evidenceDirectory) {
          await mkdir(this.evidenceDirectory, { recursive: true, mode: 0o700 });
          await appendFile(join(this.evidenceDirectory, 'requests.jsonl'), JSON.stringify({ at: new Date().toISOString(), index: this.responseIndex, model: payload.model, effort: this.requestEffort, serviceTier: this.requestedServiceTier, tools: names }) + '\n', { mode: 0o600 });
        }
        return payload;
      };
      session.subscribe(event => this.#event(event));
      this.threadId = randomUUID();
      return { thread: { id: this.threadId } };
    }
    if (method === 'turn/start') {
      this.session.setThinkingLevel('low');
      const text = params.input.filter(item => item.type === 'text').map(item => item.text).join('\n\n');
      const images = await Promise.all(params.input.filter(item => ['localImage', 'image'].includes(item.type)).map(async item => {
        if (item.type === 'localImage') return { type: 'image', mimeType: 'image/jpeg', data: (await readFile(item.path)).toString('base64') };
        const match = /^data:([^;]+);base64,(.*)$/s.exec(item.url);
        if (!match) throw new Error('Invalid observation image');
        return { type: 'image', mimeType: match[1], data: match[2] };
      }));
      this.turnId = randomUUID();
      this.emit('message', { method: 'turn/started', params: { turn: { id: this.turnId } } });
      this.running = this.session.prompt(text, { images, expandPromptTemplates: false }).then(() => {
        if (this.#closed) return;
        const last = this.session.messages.filter(message => message.role === 'assistant').at(-1);
        const failed = ['error', 'aborted'].includes(last?.stopReason);
        this.emit('message', { method: 'turn/completed', params: { turn: { id: this.turnId, status: failed ? 'failed' : 'completed', error: failed ? { message: last.errorMessage ?? 'pi model interrupted' } : null } } });
      }).catch(error => { if (!this.#closed) this.emit('disconnected', error); });
      return { turn: { id: this.turnId } };
    }
    if (method === 'turn/interrupt') { await this.session?.abort(); return {}; }
    throw new Error(`Unsupported pi session method ${method}`);
  }

  #warnTier(reason) {
    if (this.tierWarning) return;
    this.tierWarning = true;
    this.emit('warning', `Requested service tier ${this.serviceTier}: ${reason}. Fast is not confirmed. Rejected requests retry once with explicit default; later requests retain the configured tier.`);
  }

  #event(event) {
    if (event.type !== 'message_end' || event.message.role !== 'assistant' || this.responseStarted == null) return;
    const message = event.message;
    const usage = message.usage;
    this.emit('response', {
      index: this.responseIndex, model: message.model, effort: this.requestEffort, requestedServiceTier: this.requestedServiceTier, servedServiceTier: this.servedServiceTier ?? null,
      firstDeltaMilliseconds: this.firstDelta == null ? null : this.firstDelta - this.responseStarted,
      responseMilliseconds: performance.now() - this.responseStarted,
      inputTokens: usage.input + usage.cacheRead, cachedInputTokens: usage.cacheRead,
      outputTokens: usage.output, stopReason: message.stopReason,
      timingSource: 'pi provider payload to first provider delta, when available',
    });
    this.emit('assistant-text', message.content.filter(part => part.type === 'text').map(part => part.text).join('\n'));
    for (const part of message.content) if (part.type === 'text') {
      this.emit('message', { method: 'item/completed', params: { item: { type: 'agentMessage', text: part.text } } });
    }
  }

  send(message) {
    const pending = this.#pending.get(message.id);
    if (!pending) return;
    this.#pending.delete(message.id);
    if (message.error) return pending.reject(new Error(message.error.message));
    const result = message.result;
    const content = result.contentItems.map(item => {
      if (item.type === 'inputText') return { type: 'text', text: item.text };
      const match = /^data:([^;]+);base64,(.*)$/s.exec(item.imageUrl);
      if (!match) throw new Error('Invalid tool image');
      return { type: 'image', mimeType: match[1], data: match[2] };
    });
    pending.resolve({ content, details: { success: result.success } });
  }

  close() {
    this.#closed = true;
    for (const pending of this.#pending.values()) pending.reject(new Error('Task stopped'));
    this.#pending.clear();
    if (this.session) void this.session.abort().finally(() => this.session.dispose());
  }
}
