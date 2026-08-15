import { randomUUID } from 'node:crypto';
import { pool } from '../db.js';
import { loadHomeSnapshot } from '../ai/ha-context.js';
import { haRest, haWaitForState } from '../services/home-assistant.js';
import { SceneEngine } from './scene-engine.js';

const loadJsonState = async (userId, key, fallback) => {
  const { rows } = await pool.query('SELECT value FROM user_app_state WHERE user_id=$1 AND state_key=$2', [userId, key]);
  return rows[0]?.value ?? fallback;
};

const saveJsonState = (userId, key, value) => pool.query(
  `INSERT INTO user_app_state (user_id,state_key,value,updated_at) VALUES ($1,$2,$3::jsonb,NOW())
   ON CONFLICT (user_id,state_key) DO UPDATE SET value=EXCLUDED.value,updated_at=NOW()`,
  [userId, key, JSON.stringify(value)],
);

const callService = (userId, domain, service, entityId, data) => haRest(
  userId, `/api/services/${domain}/${service}`,
  { method: 'POST', body: JSON.stringify({ entity_id: entityId, ...data }) },
);

const verifyState = async (userId, entityId, expected, timeoutMs) => {
  try {
    const state = await haRest(userId, `/api/states/${encodeURIComponent(entityId)}`);
    if (state?.state === expected) return true;
  } catch { /* state_changed may still confirm the action */ }
  try { return await haWaitForState(userId, entityId, expected, timeoutMs); }
  catch { return false; }
};

export const sceneEngine = new SceneEngine({
  loadSnapshot: loadHomeSnapshot,
  loadSettings: async (userId, sceneId) => (await loadJsonState(userId, 'preset_scene_settings', {}))[sceneId] || {},
  loadTags: (userId) => loadJsonState(userId, 'device_tags', {}),
  callService,
  verifyState,
  setHomeMode: (userId, mode) => saveJsonState(userId, 'home_mode', { mode, changedAt: new Date().toISOString() }),
  saveExecution: (userId, report) => pool.query(
    `INSERT INTO scene_executions (id,user_id,home_id,scene_id,status,report,started_at,finished_at)
     VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7,$8)`,
    [randomUUID(), userId, report.homeId, report.sceneId, report.status, JSON.stringify(report), report.startedAt, report.finishedAt],
  ),
});
