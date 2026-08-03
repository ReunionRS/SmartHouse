import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { pool } from '../db.js';

export const signUserToken = (user) =>
  jwt.sign({ sub: user.id }, config.jwtSecret, { expiresIn: '30d' });

export const authRequired = async (req, res, next) => {
  try {
    const header = String(req.headers.authorization || '');
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    if (!token) return res.status(401).json({ error: 'Требуется авторизация' });
    const payload = jwt.verify(token, config.jwtSecret);
    const { rows } = await pool.query(
      'SELECT id, email, fio, avatar_url FROM users WHERE id = $1 LIMIT 1',
      [payload.sub],
    );
    if (!rows.length) return res.status(401).json({ error: 'Сессия недействительна' });
    req.user = rows[0];
    next();
  } catch {
    res.status(401).json({ error: 'Сессия недействительна' });
  }
};
