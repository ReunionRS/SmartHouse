import { randomUUID } from 'node:crypto';
import { pool } from '../db.js';

export const ensureConversation = async ({ id, userId, homeId = '' }) => {
  const conversationId = id || randomUUID();
  const { rows } = await pool.query(
    `INSERT INTO ai_conversations (id, user_id, home_id)
     VALUES ($1, $2, $3)
     ON CONFLICT (id) DO UPDATE SET updated_at = NOW()
     WHERE ai_conversations.user_id = EXCLUDED.user_id
     RETURNING id`,
    [conversationId, userId, homeId],
  );
  if (!rows.length) throw Object.assign(new Error('Диалог не найден'), { statusCode: 404 });
  return conversationId;
};

export const loadRecentMessages = async ({ conversationId, userId, limit = 12 }) => {
  const { rows } = await pool.query(
    `SELECT m.role, m.content FROM ai_messages m
     JOIN ai_conversations c ON c.id = m.conversation_id
     WHERE m.conversation_id = $1 AND c.user_id = $2
     ORDER BY m.created_at DESC LIMIT $3`,
    [conversationId, userId, limit],
  );
  return rows.reverse();
};

export const saveMessage = ({ conversationId, role, content, responseType = 'text' }) =>
  pool.query(
    'INSERT INTO ai_messages (id, conversation_id, role, content, response_type) VALUES ($1,$2,$3,$4,$5)',
    [randomUUID(), conversationId, role, content, responseType],
  );

export const saveAudit = ({ userId, homeId = '', conversationId, tool, target = '', result, latencyMs }) =>
  pool.query(
    `INSERT INTO ai_audit_log (id,user_id,home_id,conversation_id,tool,target,result,latency_ms)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
    [randomUUID(), userId, homeId, conversationId, tool, target, result, latencyMs],
  );

export const listConversations = async (userId) => {
  const { rows } = await pool.query(
    `SELECT c.id, c.home_id AS "homeId", c.created_at AS "createdAt", c.updated_at AS "updatedAt",
      COALESCE((SELECT content FROM ai_messages WHERE conversation_id=c.id ORDER BY created_at DESC LIMIT 1), '') AS preview
     FROM ai_conversations c WHERE c.user_id=$1 ORDER BY c.updated_at DESC LIMIT 50`,
    [userId],
  );
  return rows;
};

export const getConversationMessages = async ({ id, userId }) => {
  const { rows } = await pool.query(
    `SELECT m.id,m.role,m.content,m.response_type AS "type",m.created_at AS "createdAt"
     FROM ai_messages m JOIN ai_conversations c ON c.id=m.conversation_id
     WHERE c.id=$1 AND c.user_id=$2 ORDER BY m.created_at`,
    [id, userId],
  );
  return rows;
};

export const deleteConversation = async ({ id, userId }) => {
  const result = await pool.query('DELETE FROM ai_conversations WHERE id=$1 AND user_id=$2', [id, userId]);
  return result.rowCount > 0;
};
