import { Router } from 'express';
import { randomUUID } from 'crypto';
import { pool } from '../db.js';
import { asyncRoute } from '../lib/http.js';
import { authRequired } from '../middleware/auth.js';

const router = Router();
router.use(authRequired);

router.post('/register', asyncRoute(async (req, res) => {
  const token = String(req.body.token || '').trim();
  if (!token) return res.status(400).json({ error: 'token обязателен' });
  await pool.query(
    `INSERT INTO push_tokens (id,user_id,token,token_type,platform,app_version,locale)
     VALUES ($1,$2,$3,$4,$5,$6,$7)
     ON CONFLICT (token) DO UPDATE SET user_id=EXCLUDED.user_id, token_type=EXCLUDED.token_type,
       platform=EXCLUDED.platform, app_version=EXCLUDED.app_version, locale=EXCLUDED.locale, updated_at=NOW()`,
    [randomUUID(), req.user.id, token, String(req.body.tokenType || 'fcm'), String(req.body.platform || ''), String(req.body.appVersion || ''), String(req.body.locale || '')],
  );
  res.json({ ok: true });
}));

router.delete('/unregister', asyncRoute(async (req, res) => {
  await pool.query('DELETE FROM push_tokens WHERE user_id=$1 AND token=$2', [req.user.id, String(req.body.token || '')]);
  res.json({ ok: true });
}));

export default router;
