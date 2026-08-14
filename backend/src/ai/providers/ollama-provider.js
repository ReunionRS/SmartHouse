import { LlmProvider } from './llm-provider.js';

export class OllamaProvider extends LlmProvider {
  constructor({ baseUrl, model, apiKey = '', timeoutMs = 60000, fetchImpl = fetch }) {
    super();
    this.baseUrl = baseUrl.replace(/\/$/, '');
    this.model = model;
    this.apiKey = apiKey;
    this.timeoutMs = timeoutMs;
    this.fetch = fetchImpl;
  }

  async chatWithTools(messages, tools) {
    let response;
    try {
      response = await this.fetch(`${this.baseUrl}/api/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(this.apiKey ? { Authorization: `Bearer ${this.apiKey}` } : {}),
        },
        body: JSON.stringify({
          model: this.model,
          messages,
          tools,
          stream: false,
          keep_alive: '15m',
          options: {
            temperature: 0.2,
            top_p: 0.8,
            repeat_penalty: 1.08,
          },
        }),
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch (cause) {
      const timeout = cause?.name === 'TimeoutError';
      const error = new Error(timeout
        ? 'Qwen не успела ответить. Попробуйте ещё раз.'
        : 'Локальная модель Qwen недоступна');
      error.code = timeout ? 'LLM_TIMEOUT' : 'LLM_UNAVAILABLE';
      error.statusCode = 503;
      throw error;
    }
    const body = await response.json().catch(() => null);
    if (!response.ok || !body?.message) {
      const error = new Error(body?.error || 'Локальная модель Qwen недоступна');
      error.code = 'LLM_UNAVAILABLE';
      error.statusCode = 503;
      throw error;
    }
    return { message: body.message, usage: body.prompt_eval_count == null ? null : {
      promptTokens: body.prompt_eval_count,
      completionTokens: body.eval_count || 0,
    } };
  }

  async healthCheck() {
    try {
      const response = await this.fetch(`${this.baseUrl}/api/tags`, {
        signal: AbortSignal.timeout(Math.min(this.timeoutMs, 5000)),
      });
      if (!response.ok) return false;
      const body = await response.json();
      return Array.isArray(body.models) && body.models.some((item) =>
        String(item.name || '').split(':')[0] === this.model.split(':')[0]);
    } catch {
      return false;
    }
  }
}
