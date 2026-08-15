import { Router } from 'express';
import { config } from '../config.js';
import { asyncRoute } from '../lib/http.js';
import { authRequired } from '../middleware/auth.js';
import { aiOrchestrator, aiProvider } from '../ai/ai-service.js';
import {
  deleteConversation,
  ensureConversation,
  getConversationMessages,
  listConversations,
  loadRecentMessages,
  saveMessage,
} from '../ai/conversation-store.js';
import { takeConfirmation } from '../ai/safety/confirmation-service.js';
import { executeAiTool } from '../ai/tools/ai-tools.js';

const router = Router();
const requests = new Map();
router.use(authRequired);
router.use((req, res, next) => {
  const now = Date.now();
  const current = requests.get(req.user.id) || [];
  const recent = current.filter((time) => now - time < 60000);
  if (recent.length >= 20) return res.status(429).json({ error: 'Слишком много запросов к ассистенту' });
  recent.push(now);
  requests.set(req.user.id, recent);
  next();
});

router.get('/health', asyncRoute(async (_req, res) => {
  res.json({ enabled: config.ai.enabled, provider: config.ai.provider, model: config.ai.model, available: config.ai.enabled && await aiProvider.healthCheck() });
}));

router.get('/conversations', asyncRoute(async (req, res) => {
  res.json({ items: await listConversations(req.user.id) });
}));

router.get('/conversations/:id/messages', asyncRoute(async (req, res) => {
  res.json({ items: await getConversationMessages({ id: req.params.id, userId: req.user.id }) });
}));

router.delete('/conversations/:id', asyncRoute(async (req, res) => {
  const removed = await deleteConversation({ id: req.params.id, userId: req.user.id });
  if (!removed) return res.status(404).json({ error: 'Диалог не найден' });
  res.json({ ok: true });
}));

router.post('/chat', asyncRoute(async (req, res) => {
  if (!config.ai.enabled) return res.status(503).json({ error: 'AI-ассистент отключён' });
  const message = String(req.body.message || '').trim();
  if (!message || message.length > 2000) return res.status(400).json({ error: 'Сообщение должно содержать от 1 до 2000 символов' });
  const homeId = String(req.body.homeId || '').slice(0, 100);
  const requestedLanguage = String(req.body.language || '').toLowerCase();
  const language = ['ru', 'en', 'udm', 'tt'].includes(requestedLanguage)
    ? requestedLanguage
    : '';
  const conversationId = await ensureConversation({ id: String(req.body.conversationId || '') || null, userId: req.user.id, homeId });
  const history = await loadRecentMessages({ conversationId, userId: req.user.id });
  await saveMessage({ conversationId, role: 'user', content: message });
  const answer = await aiOrchestrator.chat({
    userId: req.user.id,
    userName: String(req.user.fio || '').trim(),
    homeId,
    conversationId,
    history,
    message,
    language,
  });
  await saveMessage({ conversationId, role: 'assistant', content: answer.message, responseType: answer.type });
  res.json({ conversationId, message: answer.message, type: answer.type, data: answer.data, actions: [], suggestions: [] });
}));

router.post('/confirm-action/:confirmationId', asyncRoute(async (req, res) => {
  const item = await takeConfirmation({
    id: req.params.confirmationId,
    userId: req.user.id,
    nextStatus: 'confirmed',
  });
  const result = await executeAiTool({
    userId: req.user.id,
    name: item.tool,
    args: item.arguments,
    confirmed: true,
  });
  res.json({ ok: result.success === true, result });
}));

router.post('/cancel-action/:confirmationId', asyncRoute(async (req, res) => {
  await takeConfirmation({
    id: req.params.confirmationId,
    userId: req.user.id,
    nextStatus: 'cancelled',
  });
  res.json({ ok: true });
}));

export default router;
