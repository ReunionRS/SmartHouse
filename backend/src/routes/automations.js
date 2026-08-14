import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import { asyncRoute } from '../lib/http.js';
import { authRequired } from '../middleware/auth.js';
import { haRest } from '../services/home-assistant.js';
import { loadHomeSnapshot } from '../ai/ha-context.js';

const router = Router();
router.use(authRequired);

router.get('/', asyncRoute(async (req, res) => {
  const states = await haRest(req.user.id, '/api/states');
  const items = states
    .filter((item) => String(item.entity_id || '').startsWith('automation.'))
    .map((item) => ({
      id: item.entity_id,
      name: item.attributes?.friendly_name || item.entity_id,
      enabled: item.state === 'on',
      lastTriggered: item.attributes?.last_triggered || null,
    }));
  res.json({ items });
}));

router.post('/', asyncRoute(async (req, res) => {
  const draft = req.body?.draft;
  if (!draft || typeof draft !== 'object') return res.status(400).json({ error: 'Некорректный черновик' });
  const snapshot = await loadHomeSnapshot(req.user.id);
  const byId = new Map(snapshot.entities.map((item) => [item.entity_id, item]));
  const trigger = byId.get(String(draft.trigger?.entity_id || ''));
  if (!trigger || !['binary_sensor', 'sensor'].includes(trigger.domain)) {
    return res.status(400).json({ error: 'Датчик автоматизации не найден' });
  }
  const actions = Array.isArray(draft.actions) ? draft.actions.slice(0, 20) : [];
  if (!actions.length) return res.status(400).json({ error: 'Не выбраны устройства действия' });
  for (const action of actions) {
    const entity = byId.get(String(action.entity_id || ''));
    if (!entity || !['light', 'switch'].includes(entity.domain)) {
      return res.status(400).json({ error: 'Устройство действия не найдено' });
    }
    if (!['turn_on', 'turn_off', 'flash'].includes(action.action)) {
      return res.status(400).json({ error: 'Действие не поддерживается' });
    }
    if (action.action === 'flash' && entity.domain !== 'light') {
      return res.status(400).json({ error: 'Мигание поддерживается только лампами' });
    }
  }
  const id = `smarthouse_${randomUUID().replaceAll('-', '')}`;
  const automation = {
    alias: String(draft.name || 'SmartHouse automation').slice(0, 100),
    description: String(draft.description || '').slice(0, 1000),
    mode: 'single',
    trigger: [{ platform: 'state', entity_id: trigger.entity_id, to: draft.trigger?.state === 'off' ? 'off' : 'on' }],
    condition: [],
    action: actions.flatMap((item) => item.action === 'flash'
      ? [{ service: 'light.turn_on', target: { entity_id: item.entity_id }, data: { flash: 'long' } }]
      : [{ service: `${byId.get(item.entity_id).domain}.${item.action}`, target: { entity_id: item.entity_id } }]),
  };
  await haRest(req.user.id, `/api/config/automation/config/${id}`, {
    method: 'POST', body: JSON.stringify(automation),
  });
  await haRest(req.user.id, '/api/services/automation/reload', { method: 'POST', body: '{}' });
  res.status(201).json({ ok: true, id, name: automation.alias });
}));

export default router;
