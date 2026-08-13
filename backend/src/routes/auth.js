import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { randomUUID, createHash } from 'crypto';
import { pool } from '../db.js';
import { asyncRoute } from '../lib/http.js';
import { authRequired, signUserToken } from '../middleware/auth.js';

const router = Router();
const publicUser = (user) => ({
  id: user.id,
  email: user.email,
  fio: user.fio || '',
  avatarUrl: user.avatar_url || '',
});

router.post('/register', asyncRoute(async (req, res) => {
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');
  if (!/^\S+@\S+\.\S+$/.test(email)) return res.status(400).json({ error: 'Некорректный email' });
  if (password.length < 8) return res.status(400).json({ error: 'Пароль должен содержать не менее 8 символов' });
  const passwordHash = await bcrypt.hash(password, 12);
  try {
    const { rows } = await pool.query(
      'INSERT INTO users (id, email, password_hash) VALUES ($1,$2,$3) RETURNING *',
      [randomUUID(), email, passwordHash],
    );
    res.status(201).json({ token: signUserToken(rows[0]), user: publicUser(rows[0]) });
  } catch (error) {
    if (error.code === '23505') return res.status(409).json({ error: 'Email уже зарегистрирован' });
    throw error;
  }
}));

router.post('/login', asyncRoute(async (req, res) => {
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');
  const { rows } = await pool.query('SELECT * FROM users WHERE email = $1 LIMIT 1', [email]);
  if (!rows.length || !(await bcrypt.compare(password, rows[0].password_hash))) {
    return res.status(401).json({ error: 'Неверный email или пароль' });
  }
  res.json({ token: signUserToken(rows[0]), user: publicUser(rows[0]) });
}));

router.get('/me', authRequired, (req, res) => res.json({ user: publicUser(req.user) }));

router.post('/one-time-login', asyncRoute(async (req, res) => {
  const token = String(req.body.token || '');
  if (!token) return res.status(400).json({ error: 'Токен обязателен' });

  const tokenHash = createHash('sha256').update(token, 'utf8').digest('hex');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      `SELECT t.id, t.user_id, users.email, users.fio, users.avatar_url
       FROM ha_one_time_tokens t
       JOIN users ON users.id = t.user_id
       WHERE t.token_hash = $1 AND t.consumed_at IS NULL AND t.expires_at > NOW()
       FOR UPDATE`,
      [tokenHash],
    );
    if (!rows.length) {
      await client.query('ROLLBACK');
      return res.status(401).json({ error: 'Токен недействителен или истёк' });
    }
    await client.query('UPDATE ha_one_time_tokens SET consumed_at = NOW() WHERE id = $1', [rows[0].id]);
    await client.query('COMMIT');

    const user = { id: rows[0].user_id, email: rows[0].email, fio: rows[0].fio, avatar_url: rows[0].avatar_url };
    return res.json({ token: signUserToken(user), user: publicUser(user) });
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}));

export { publicUser };
export default router;
