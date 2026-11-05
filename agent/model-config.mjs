export function modelConfig(options = {}) {
  const auth = options.auth ?? process.env.POKI_AGENT_AUTH ?? (process.env.OPENAI_API_KEY ? 'api-key' : 'chatgpt');
  const model = options.model ?? process.env.POKI_AGENT_MODEL ?? 'gpt-6.1-terra';
  const serviceTier = options.serviceTier ?? process.env.POKI_AGENT_SERVICE_TIER ?? 'priority';
  if (!['api-key', 'chatgpt'].includes(auth)) throw new Error('Set POKI_AGENT_AUTH to api-key or chatgpt. Only OpenAI is supported.');
  if (!model) throw new Error('Set POKI_AGENT_MODEL or pass --model with an OpenAI model available to your account.');
  if (serviceTier !== undefined && !['default', 'auto', 'fast', 'priority', 'flex', 'ultrafast'].includes(serviceTier)) throw new Error('Invalid service tier. Set POKI_AGENT_SERVICE_TIER=default for the standard tier.');
  const baseUrl = process.env.OPENAI_BASE_URL;
  if (baseUrl) {
    const url = new URL(baseUrl);
    if (auth !== 'api-key' || url.username || url.password || url.search || url.hash ||
        !(url.href === 'https://api.openai.com/v1' || url.href === 'https://api.openai.com/v1/' ||
          url.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname))) {
      throw new Error('OPENAI_BASE_URL must be the OpenAI API or a local development server, and requires api-key mode.');
    }
  }
  return { auth, model, serviceTier, baseUrl };
}

export function safeModelError(error) {
  const message = String(error?.message ?? error ?? 'Model request failed');
  return [process.env.OPENAI_API_KEY, process.env.POKI_IPHONE_PASSCODE].filter(Boolean).reduce((text, secret) => text.replaceAll(secret, '[redacted]'), message);
}
