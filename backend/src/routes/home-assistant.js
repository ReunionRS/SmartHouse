import { Router } from 'express';
import { randomUUID } from 'crypto';
import { config } from '../config.js';
import { pool } from '../db.js';
import { asyncRoute, normalizeBaseUrl } from '../lib/http.js';
import { encryptToken } from '../lib/token-crypto.js';
import { authRequired } from '../middleware/auth.js';
import { getConnection, haWebSocket } from '../services/home-assistant.js';

export const oauthRouter = Router();
oauthRouter.get('/ha-oauth-client', (req, res) => {
  const origin = `${req.protocol}://${req.get('host')}`;
  const redirects = [`smarthouse://ha-callback/oauth2redirect`, `${origin}/ha-oauth-web-callback`, ...config.haWebRedirectUris];
  res.type('html').send(`<!doctype html><html><head>${redirects.map((url) => `<link rel="redirect_uri" href="${url}" />`).join('')}</head><body>Smart House OAuth client</body></html>`);
});
oauthRouter.get('/ha-oauth-web-callback', (req, res) => {
  const target = config.haWebAppUrl || 'http://localhost:5173';
  res.redirect(302, `${target.replace(/\/$/, '')}/ha-oauth-web-callback?${new URLSearchParams(req.query).toString()}`);
});

const router = Router();
router.use(authRequired);
router.get('/connection', asyncRoute(async (req, res) => {
  const connection = await getConnection(req.user.id);
  if (!connection) return res.json({ connected: false });
  res.json({ connected: true, item: { id: connection.id, userId: connection.user_id, houseId: connection.house_id || '', baseUrl: connection.base_url, expiresAt: connection.expires_at, status: connection.status, lastCheckedAt: connection.last_checked_at } });
}));
router.post('/connection', asyncRoute(async (req, res) => {
  const baseUrl = normalizeBaseUrl(req.body.baseUrl);
  const accessToken = String(req.body.accessToken || '');
  const refreshToken = String(req.body.refreshToken || '');
  const expiresAt = new Date(req.body.expiresAt);
  if (!accessToken || !refreshToken || Number.isNaN(expiresAt.getTime())) return res.status(400).json({ error: 'Некорректные данные подключения' });
  await pool.query(
    `INSERT INTO home_assistant_connections (id,user_id,house_id,base_url,access_token_encrypted,refresh_token_encrypted,client_id,expires_at,status,last_checked_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'connected',NOW())
     ON CONFLICT (user_id) DO UPDATE SET house_id=EXCLUDED.house_id,base_url=EXCLUDED.base_url,
       access_token_encrypted=EXCLUDED.access_token_encrypted,refresh_token_encrypted=EXCLUDED.refresh_token_encrypted,
       client_id=EXCLUDED.client_id,expires_at=EXCLUDED.expires_at,status='connected',last_checked_at=NOW(),updated_at=NOW()`,
    [randomUUID(), req.user.id, String(req.body.houseId || '') || null, baseUrl, encryptToken(accessToken), encryptToken(refreshToken), String(req.body.clientId || ''), expiresAt.toISOString()],
  );
  res.json({ ok: true });
}));
router.delete('/connection', asyncRoute(async (req, res) => {
  await pool.query('DELETE FROM home_assistant_connections WHERE user_id=$1', [req.user.id]);
  res.json({ ok: true });
}));
router.get('/rooms', asyncRoute(async (req, res) => {
  const [areas, devices, entities] = await Promise.all([
    haWebSocket(req.user.id, { type: 'config/area_registry/list' }),
    haWebSocket(req.user.id, { type: 'config/device_registry/list' }),
    haWebSocket(req.user.id, { type: 'config/entity_registry/list' }),
  ]);
  const deviceAreas = new Map(devices.map((item) => [item.id, item.area_id]));
  res.json({ items: areas.map((area) => ({ ...area, area_id: area.area_id || area.id, device_ids: devices.filter((item) => item.area_id === (area.area_id || area.id)).map((item) => item.id), entity_ids: entities.filter((item) => (item.area_id || deviceAreas.get(item.device_id)) === (area.area_id || area.id)).map((item) => item.entity_id) })) });
}));
router.post('/rooms', asyncRoute(async (req, res) => {
  const name = String(req.body.name || '').trim();
  if (!name) return res.status(400).json({ error: 'Название комнаты обязательно' });
  const item = await haWebSocket(req.user.id, { type: 'config/area_registry/create', name, aliases: req.body.aliases || [], labels: req.body.labels || [] });
  res.status(201).json({ item });
}));

export default router;
