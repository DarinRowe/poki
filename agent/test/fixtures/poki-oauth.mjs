import { ModelRuntime } from '@earendil-works/pi-coding-agent';
const create = ModelRuntime.create;
ModelRuntime.create = async function (options) {
  const runtime = await create.call(this, options);
  const provider = runtime.getProvider('openai');
  runtime.registerNativeProvider({ ...provider, auth: { oauth: {
    name: 'Synthetic ChatGPT',
    async login(interaction, options) {
      if (options.agentName !== 'Poki' || typeof options.getDeviceId !== 'function') throw new Error('Missing installation identity');
      interaction.notify({ type: 'progress', message: 'Synthetic provider accepted sign-in.' });
      if (process.env.POKI_TEST_AUTH_FAIL) throw new Error('synthetic-oauth-secret');
      return { type: 'oauth', access: 'synthetic-oauth-secret', refresh: 'synthetic-refresh', expires: Date.now() + 3600000 };
    },
    async resolve({ credential }) { return { apiKey: credential.access }; },
  } } });
  return runtime;
};
