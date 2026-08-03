import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { randomUUID } from 'crypto';
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

export { publicUser };
export default router;
