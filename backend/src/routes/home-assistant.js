import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { createHash, createHmac, randomBytes, randomUUID, timingSafeEqual } from 'crypto';
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

const pairingTokenHash = (token) =>
  createHash('sha256').update(token, 'utf8').digest('hex');

const hasValidPairingSecret = (value) => {
  const supplied = Buffer.from(String(value || ''), 'utf8');
  const expected = Buffer.from(config.haPairingSecret, 'utf8');
  return supplied.length === expected.length && timingSafeEqual(supplied, expected);
};

const hasValidHubProof = (proof, expectedHubId) => {
  try {
    const [encodedPayload, encodedSignature, extra] = String(proof || '').split('.');
    if (!encodedPayload || !encodedSignature || extra) return false;
    const supplied = Buffer.from(encodedSignature, 'base64url');
    const expected = createHmac('sha256', config.haPairingSecret)
      .update(encodedPayload, 'utf8')
      .digest();
    if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return false;
    const payload = JSON.parse(Buffer.from(encodedPayload, 'base64url').toString('utf8'));
    const issuedAt = Number(payload.issuedAt);
    const ageSeconds = Math.abs(Date.now() / 1000 - issuedAt);
    return payload.hubId === expectedHubId
      && typeof payload.nonce === 'string'
      && payload.nonce.length >= 16
      && Number.isFinite(issuedAt)
      && ageSeconds <= 5 * 60;
  } catch {
    return false;
  }
};

router.post('/pairing-sessions/consume', asyncRoute(async (req, res) => {
  if (!hasValidPairingSecret(req.get('x-smart-house-pairing-secret'))) {
    return res.status(401).json({ error: 'Недействительный ключ хаба' });
  }

  const token = String(req.body.token || '');
  const hubId = String(req.body.hubId || '').trim();
  if (!token || !hubId) {
    return res.status(400).json({ error: 'Токен и идентификатор хаба обязательны' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      `SELECT session.id, users.id AS user_id, users.email, users.fio
       FROM ha_pairing_sessions AS session
       JOIN users ON users.id = session.user_id
       WHERE session.token_hash = $1 AND session.hub_id = $2
         AND session.consumed_at IS NULL AND session.expires_at > NOW()
       FOR UPDATE OF session`,
      [pairingTokenHash(token), hubId],
    );
    if (!rows.length) {
      await client.query('ROLLBACK');
      return res.status(401).json({ error: 'Сессия подключения недействительна или истекла' });
    }
    await client.query(
      'UPDATE ha_pairing_sessions SET consumed_at = NOW() WHERE id = $1',
      [rows[0].id],
    );
    await client.query('COMMIT');

    // Create a one-time token to allow the client app to log in automatically.
    const oneTimeToken = randomBytes(32).toString('base64url');
    const oneTimeExpiresAt = new Date(Date.now() + 5 * 60 * 1000);
    await pool.query(
      `INSERT INTO ha_one_time_tokens (id, user_id, token_hash, expires_at)
       VALUES ($1, $2, $3, $4)`,
      [randomUUID(), rows[0].user_id, pairingTokenHash(oneTimeToken), oneTimeExpiresAt.toISOString()],
    );

    const deepLink = `smarthouse://one-time-login?token=${oneTimeToken}`;
    const webRedirect = `${(config.haWebAppUrl || 'http://localhost:5173').replace(/\/$/, '')}/one-time-login?token=${oneTimeToken}`;

    return res.json({
      user: {
        id: rows[0].user_id,
        email: rows[0].email,
        name: rows[0].fio || rows[0].email,
      },
      oneTime: {
        deepLink,
        webRedirect,
        expiresAt: oneTimeExpiresAt.toISOString(),
      },
    });
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}));

router.post('/local-login', asyncRoute(async (req, res) => {
  if (!hasValidPairingSecret(req.get('x-smart-house-pairing-secret'))) {
    return res.status(401).json({ error: 'Недействительный ключ хаба' });
  }
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');
  const { rows } = await pool.query(
    'SELECT id, email, fio, password_hash FROM users WHERE email = $1 LIMIT 1',
    [email],
  );
  if (!rows.length || !(await bcrypt.compare(password, rows[0].password_hash))) {
    return res.status(401).json({ error: 'Неверный email или пароль' });
  }
  return res.json({
    user: {
      id: rows[0].id,
      email: rows[0].email,
      name: rows[0].fio || rows[0].email,
    },
  });
}));

router.use(authRequired);

router.post('/pairing-sessions', asyncRoute(async (req, res) => {
  const hubId = String(req.body.hubId || '').trim();
  const pairingProof = String(req.body.pairingProof || '');
  if (!hubId || hubId.length > 128) {
    return res.status(400).json({ error: 'Некорректный идентификатор хаба' });
  }
  if (!hasValidHubProof(pairingProof, hubId)) {
    return res.status(401).json({ error: 'Не удалось подтвердить локальный хаб' });
  }

  const token = randomBytes(32).toString('base64url');
  const expiresAt = new Date(Date.now() + 5 * 60 * 1000);
  await pool.query(
    `INSERT INTO ha_pairing_sessions (id, user_id, hub_id, token_hash, expires_at)
     VALUES ($1, $2, $3, $4, $5)`,
    [randomUUID(), req.user.id, hubId, pairingTokenHash(token), expiresAt.toISOString()],
  );
  res.status(201).json({ token, hubId, expiresAt: expiresAt.toISOString() });
}));
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
