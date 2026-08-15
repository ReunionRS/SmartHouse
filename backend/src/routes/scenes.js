import { Router } from 'express';
import { asyncRoute } from '../lib/http.js';
import { authRequired } from '../middleware/auth.js';
import { getConnection } from '../services/home-assistant.js';
import { PRESET_SCENES } from '../scenes/preset-scenes.js';
import { sceneEngine } from '../scenes/scene-service.js';
import { pool } from '../db.js';

const router = Router({ mergeParams: true });
router.use(authRequired);
const running = new Map();

const requireHome = async (req, res) => {
  const connection = await getConnection(req.user.id);
  if (!connection) {
    res.status(409).json({ error: 'Home Assistant не подключён' });
    return null;
  }
  const requested = String(req.params.homeId || '');
  const actual = String(connection.house_id || connection.id);
  if (requested !== actual && requested !== 'default') {
    res.status(403).json({ error: 'Нет доступа к этому дому' });
    return null;
  }
  return actual;
};

router.get('/', asyncRoute(async (req, res) => {
  const homeId = await requireHome(req, res);
  if (!homeId) return;
  const { rows } = await pool.query(
    'SELECT value FROM user_app_state WHERE user_id=$1 AND state_key=$2',
    [req.user.id, 'preset_scene_settings'],
  );
  const settings = rows[0]?.value || {};
  res.json({ items: PRESET_SCENES.map((item) => ({ ...item, settings: settings[item.id] || {} })), homeId });
}));

router.put('/:sceneId/settings', asyncRoute(async (req, res) => {
  const homeId = await requireHome(req, res);
  if (!homeId) return;
  if (!PRESET_SCENES.some((item) => item.id === req.params.sceneId)) return res.status(404).json({ error: 'Готовая сцена не найдена' });
  const numeric = ['brightness', 'nightBrightness', 'temperature'];
  const boolean = ['turnOffLights', 'turnOffSockets', 'lockDoor'];
  const next = Object.fromEntries(Object.entries(req.body || {})
    .filter(([key, value]) => (numeric.includes(key) && Number.isFinite(Number(value)))
      || (boolean.includes(key) && typeof value === 'boolean'))
    .map(([key, value]) => [key, numeric.includes(key) ? Number(value) : value]));
  const { rows } = await pool.query('SELECT value FROM user_app_state WHERE user_id=$1 AND state_key=$2', [req.user.id, 'preset_scene_settings']);
  const settings = { ...(rows[0]?.value || {}), [req.params.sceneId]: next };
  await pool.query(
    `INSERT INTO user_app_state (user_id,state_key,value,updated_at) VALUES ($1,$2,$3::jsonb,NOW())
     ON CONFLICT (user_id,state_key) DO UPDATE SET value=EXCLUDED.value,updated_at=NOW()`,
    [req.user.id, 'preset_scene_settings', JSON.stringify(settings)],
  );
  res.json({ ok: true, sceneId: req.params.sceneId, settings: next });
}));

router.post('/:sceneId/run', asyncRoute(async (req, res) => {
  const homeId = await requireHome(req, res);
  if (!homeId) return;
  const key = `${req.user.id}:${req.params.sceneId}`;
  if (running.has(key)) return res.status(409).json({ error: 'Сцена уже выполняется', code: 'SCENE_ALREADY_RUNNING' });
  const task = sceneEngine.run({
    userId: req.user.id, homeId, sceneId: req.params.sceneId, confirmed: req.body?.confirmed === true,
  });
  running.set(key, task);
  try { res.json(await task); } finally { running.delete(key); }
}));

export default router;
