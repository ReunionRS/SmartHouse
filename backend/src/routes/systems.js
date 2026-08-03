import { Router } from 'express';
import { asyncRoute } from '../lib/http.js';
import { authRequired } from '../middleware/auth.js';
import { haRest } from '../services/home-assistant.js';

const router = Router();
router.use(authRequired);

router.get('/status', asyncRoute(async (req, res) => {
  const states = await haRest(req.user.id, '/api/states');
  const domain = String(req.query.domain || '').toLowerCase();
  const items = states
    .filter((item) => !domain || String(item.entity_id || '').startsWith(`${domain}.`))
    .map((item) => ({
      entityId: item.entity_id || '',
      domain: String(item.entity_id || '').split('.')[0],
      state: item.state ?? '',
      friendlyName: item.attributes?.friendly_name || item.entity_id || '',
      unit: item.attributes?.unit_of_measurement || '',
      deviceClass: item.attributes?.device_class || '',
      icon: item.attributes?.icon || '',
      lastChanged: item.last_changed || '',
      lastUpdated: item.last_updated || '',
      attributes: item.attributes || {},
    }));
  res.json({ items });
}));

router.post('/service', asyncRoute(async (req, res) => {
  const domain = String(req.body.domain || '').trim();
  const service = String(req.body.service || '').trim();
  if (!/^[a-z0-9_]+$/.test(domain) || !/^[a-z0-9_]+$/.test(service)) {
    return res.status(400).json({ error: 'Некорректная команда' });
  }
  const result = await haRest(req.user.id, `/api/services/${domain}/${service}`, {
    method: 'POST',
    body: JSON.stringify(req.body.data || {}),
  });
  res.json({ ok: true, result });
}));

export default router;
