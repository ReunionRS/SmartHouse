import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import { asyncRoute } from '../lib/http.js';
import { authRequired } from '../middleware/auth.js';
import { haRest } from '../services/home-assistant.js';
import { loadHomeSnapshot } from '../ai/ha-context.js';
import { pool } from '../db.js';

const router = Router();
router.use(authRequired);

const loadLocalAutomations = async (userId) => {
  const { rows } = await pool.query(
    `SELECT value FROM user_app_state WHERE user_id=$1 AND state_key='local_automations'`,
    [userId],
  );
  return Array.isArray(rows[0]?.value) ? rows[0].value : [];
};

const saveLocalAutomations = (userId, items) => pool.query(
  `INSERT INTO user_app_state (user_id,state_key,value)
   VALUES ($1,'local_automations',$2::jsonb)
   ON CONFLICT (user_id,state_key)
   DO UPDATE SET value=EXCLUDED.value,updated_at=NOW()`,
  [userId, JSON.stringify(items)],
);

router.get('/', asyncRoute(async (req, res) => {
  const states = await haRest(req.user.id, '/api/states');
  const haItems = states
    .filter((item) => String(item.entity_id || '').startsWith('automation.'))
    .map((item) => ({
      id: item.entity_id,
      name: item.attributes?.friendly_name || item.entity_id,
      enabled: item.state === 'on',
      lastTriggered: item.attributes?.last_triggered || null,
    }));
  const { rows } = await pool.query(
    `SELECT value FROM user_app_state WHERE user_id=$1 AND state_key='local_automations'`,
    [req.user.id],
  );
  const localItems = Array.isArray(rows[0]?.value) ? rows[0].value : [];
  res.json({ items: [...haItems, ...localItems] });
}));

router.put('/:id', asyncRoute(async (req, res) => {
  const items = await loadLocalAutomations(req.user.id);
  const index = items.findIndex((item) => item.id === req.params.id && item.source === 'smart_house');
  if (index < 0) return res.status(404).json({ error: 'Локальная автоматизация не найдена' });
  const at = String(req.body.triggerTime || '');
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(at)) return res.status(400).json({ error: 'Некорректное время' });
  const action = String(req.body.actionType || '');
  if (!['turn_on', 'turn_off', 'toggle'].includes(action)) return res.status(400).json({ error: 'Некорректное действие' });
  const deviceId = String(req.body.actionDeviceId || '');
  const { rows } = await pool.query(
    `SELECT value FROM user_app_state WHERE user_id=$1 AND state_key='room_devices'`,
    [req.user.id],
  );
  const devices = Array.isArray(rows[0]?.value) ? rows[0].value : [];
  const device = devices.find((item) => String(item.id) === deviceId);
  if (!device) return res.status(400).json({ error: 'Устройство не найдено' });
  const domain = ['switch', 'socket'].includes(String(device.type)) ? 'switch' : 'light';
  items[index] = {
    ...items[index],
    name: String(req.body.name || items[index].name).slice(0, 100),
    enabled: req.body.enabled !== false,
    trigger: { type: 'time', at },
    actions: [{
      entity_id: deviceId,
      name: String(device.name || deviceId),
      domain,
      local: true,
      action,
    }],
  };
  await saveLocalAutomations(req.user.id, items);
  res.json({ ok: true, item: items[index] });
}));

router.delete('/:id', asyncRoute(async (req, res) => {
  const items = await loadLocalAutomations(req.user.id);
  const next = items.filter((item) => !(item.id === req.params.id && item.source === 'smart_house'));
  if (next.length === items.length) return res.status(404).json({ error: 'Локальная автоматизация не найдена' });
  await saveLocalAutomations(req.user.id, next);
  res.json({ ok: true });
}));

router.post('/', asyncRoute(async (req, res) => {
  const draft = req.body?.draft;
  if (!draft || typeof draft !== 'object') return res.status(400).json({ error: 'Некорректный черновик' });
  const snapshot = await loadHomeSnapshot(req.user.id);
  const byId = new Map(snapshot.entities.map((item) => [item.entity_id, item]));
  if (Array.isArray(draft.automations)) {
    const items = draft.automations.slice(0, 10);
    if (!items.length) return res.status(400).json({ error: 'Расписание пустое' });
    const allActions = items.flatMap((item) => Array.isArray(item.actions) ? item.actions : []);
    if (allActions.length && allActions.every((action) => action.local === true)) {
      const localItems = items.map((item) => ({
        id: `local_automation_${randomUUID()}`,
        name: String(item.name || draft.name || 'SmartHouse schedule').slice(0, 100),
        enabled: true,
        lastTriggered: null,
        source: 'smart_house',
        trigger: item.trigger,
        actions: item.actions,
      }));
      const { rows } = await pool.query(
        `SELECT value FROM user_app_state WHERE user_id=$1 AND state_key='local_automations'`,
        [req.user.id],
      );
      const current = Array.isArray(rows[0]?.value) ? rows[0].value : [];
      await pool.query(
        `INSERT INTO user_app_state (user_id,state_key,value)
         VALUES ($1,'local_automations',$2::jsonb)
         ON CONFLICT (user_id,state_key)
         DO UPDATE SET value=EXCLUDED.value,updated_at=NOW()`,
        [req.user.id, JSON.stringify([...current, ...localItems])],
      );
      return res.status(201).json({
        ok: true,
        ids: localItems.map((item) => item.id),
        name: String(draft.name || 'Расписание'),
        count: localItems.length,
        source: 'smart_house',
      });
    }
    const prepared = items.map((item) => {
      const at = String(item.trigger?.at || '');
      if (item.trigger?.type !== 'time' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(at)) {
        throw Object.assign(new Error('Некорректное время запуска'), { statusCode: 400 });
      }
      const actions = Array.isArray(item.actions) ? item.actions.slice(0, 20) : [];
      if (!actions.length) throw Object.assign(new Error('Не выбрано действие'), { statusCode: 400 });
      for (const action of actions) {
        const entity = byId.get(String(action.entity_id || ''));
        if (!entity || !['light', 'switch'].includes(entity.domain)) {
          throw Object.assign(new Error('Устройство действия не найдено'), { statusCode: 400 });
        }
        if (!['turn_on', 'turn_off'].includes(action.action)) {
          throw Object.assign(new Error('Действие не поддерживается'), { statusCode: 400 });
        }
      }
      return {
        id: `smarthouse_${randomUUID().replaceAll('-', '')}`,
        config: {
          alias: String(item.name || draft.name || 'SmartHouse schedule').slice(0, 100),
          description: String(draft.description || '').slice(0, 1000),
          mode: 'single',
          trigger: [{ platform: 'time', at }],
          condition: [],
          action: actions.map((action) => ({
            service: `${byId.get(action.entity_id).domain}.${action.action}`,
            target: { entity_id: action.entity_id },
          })),
        },
      };
    });
    for (const item of prepared) {
      await haRest(req.user.id, `/api/config/automation/config/${item.id}`, {
        method: 'POST', body: JSON.stringify(item.config),
      });
    }
    await haRest(req.user.id, '/api/services/automation/reload', { method: 'POST', body: '{}' });
    return res.status(201).json({
      ok: true,
      ids: prepared.map((item) => item.id),
      name: String(draft.name || 'Расписание'),
      count: prepared.length,
    });
  }
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
