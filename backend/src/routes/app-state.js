import { Router } from 'express';
import { pool } from '../db.js';
import { asyncRoute } from '../lib/http.js';
import { authRequired } from '../middleware/auth.js';

const router = Router();
const allowedKeys = new Set(['rooms', 'room_devices', 'room_types', 'scenes']);

router.use(authRequired);

router.get('/:key', asyncRoute(async (req, res) => {
  if (!allowedKeys.has(req.params.key)) {
    return res.status(404).json({ error: 'Неизвестный тип локальных данных' });
  }
  const { rows } = await pool.query(
    'SELECT value, updated_at FROM user_app_state WHERE user_id=$1 AND state_key=$2',
    [req.user.id, req.params.key],
  );
  res.json({ value: rows[0]?.value ?? [], updatedAt: rows[0]?.updated_at ?? null });
}));

router.put('/:key', asyncRoute(async (req, res) => {
  if (!allowedKeys.has(req.params.key)) {
    return res.status(404).json({ error: 'Неизвестный тип локальных данных' });
  }
  if (!Array.isArray(req.body.value)) {
    return res.status(400).json({ error: 'Ожидается массив данных' });
  }
  await pool.query(
    `INSERT INTO user_app_state (user_id,state_key,value)
     VALUES ($1,$2,$3::jsonb)
     ON CONFLICT (user_id,state_key)
     DO UPDATE SET value=EXCLUDED.value,updated_at=NOW()`,
    [req.user.id, req.params.key, JSON.stringify(req.body.value)],
  );
  res.json({ ok: true });
}));

export default router;
