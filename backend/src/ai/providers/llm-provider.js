export class LlmProvider {
  async chatWithTools(_messages, _tools) {
    throw new Error('chatWithTools must be implemented');
  }

  async healthCheck() {
    throw new Error('healthCheck must be implemented');
  }
}
