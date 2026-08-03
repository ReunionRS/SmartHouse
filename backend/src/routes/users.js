import { Router } from 'express';
import bcrypt from 'bcryptjs';
import multer from 'multer';
import path from 'path';
import { randomUUID } from 'crypto';
import { pool } from '../db.js';
import { asyncRoute } from '../lib/http.js';
import { authRequired } from '../middleware/auth.js';

const router = Router();
const upload = multer({
  storage: multer.diskStorage({
    destination: 'uploads/avatars',
    filename: (_req, file, done) => done(null, `${randomUUID()}${path.extname(file.originalname).toLowerCase()}`),
  }),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, done) => done(null, ['image/jpeg', 'image/png', 'image/webp'].includes(file.mimetype)),
});

router.use(authRequired);
router.patch('/me', asyncRoute(async (req, res) => {
  const fio = String(req.body.fio || '').trim();
  if (fio.length < 2 || fio.length > 80) return res.status(400).json({ error: 'Некорректное имя' });
  await pool.query('UPDATE users SET fio = $2, updated_at = NOW() WHERE id = $1', [req.user.id, fio]);
  res.json({ fio });
}));

router.post('/me/password', asyncRoute(async (req, res) => {
  const currentPassword = String(req.body.currentPassword || '');
  const newPassword = String(req.body.newPassword || '');
  if (newPassword.length < 8) return res.status(400).json({ error: 'Новый пароль слишком короткий' });
  const { rows } = await pool.query('SELECT password_hash FROM users WHERE id = $1', [req.user.id]);
  if (!(await bcrypt.compare(currentPassword, rows[0].password_hash))) {
    return res.status(400).json({ error: 'Текущий пароль указан неверно' });
  }
  await pool.query('UPDATE users SET password_hash = $2, updated_at = NOW() WHERE id = $1', [req.user.id, await bcrypt.hash(newPassword, 12)]);
  res.json({ ok: true });
}));

router.post('/me/avatar', upload.single('file'), asyncRoute(async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Нужен файл JPEG, PNG или WebP' });
  const avatarUrl = `/uploads/avatars/${req.file.filename}`;
  await pool.query('UPDATE users SET avatar_url = $2, updated_at = NOW() WHERE id = $1', [req.user.id, avatarUrl]);
  res.json({ avatarUrl });
}));

export default router;
