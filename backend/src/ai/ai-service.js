import { config } from '../config.js';
import { AiOrchestrator } from './ai-orchestrator.js';
import { OllamaProvider } from './providers/ollama-provider.js';

const provider = new OllamaProvider({
  baseUrl: config.ai.baseUrl,
  model: config.ai.model,
  apiKey: config.ai.apiKey,
  timeoutMs: config.ai.timeoutMs,
});

export const aiOrchestrator = new AiOrchestrator({ provider });
export const aiProvider = provider;
