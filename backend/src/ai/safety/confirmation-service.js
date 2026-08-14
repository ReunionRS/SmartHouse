import { randomUUID } from 'node:crypto';
import { config } from '../../config.js';
import { pool } from '../../db.js';

export const createConfirmation = async ({ userId, conversationId, tool, args }) => {
  const id = randomUUID();
  const expiresAt = new Date(Date.now() + config.ai.confirmationTtlSeconds * 1000);
  await pool.query(
    `INSERT INTO ai_action_confirmations
      (id,user_id,conversation_id,tool,arguments,expires_at)
     VALUES ($1,$2,$3,$4,$5,$6)`,
    [id, userId, conversationId, tool, JSON.stringify(args || {}), expiresAt],
  );
  return { id, action: tool, arguments: args || {}, expiresAt: expiresAt.toISOString() };
};

export const takeConfirmation = async ({ id, userId, nextStatus }) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      `SELECT * FROM ai_action_confirmations
       WHERE id=$1 AND user_id=$2 FOR UPDATE`,
      [id, userId],
    );
    const item = rows[0];
    if (!item) throw Object.assign(new Error('Подтверждение не найдено'), { statusCode: 404 });
    if (item.status !== 'pending') throw Object.assign(new Error('Подтверждение уже использовано'), { statusCode: 409 });
    if (new Date(item.expires_at).getTime() <= Date.now()) {
      await client.query("UPDATE ai_action_confirmations SET status='expired', consumed_at=NOW() WHERE id=$1", [id]);
      await client.query('COMMIT');
      throw Object.assign(new Error('Время подтверждения истекло'), { statusCode: 410, code: 'ACTION_CONFIRMATION_EXPIRED' });
    }
    await client.query(
      'UPDATE ai_action_confirmations SET status=$2, consumed_at=NOW() WHERE id=$1',
      [id, nextStatus],
    );
    await client.query('COMMIT');
    return item;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
};
