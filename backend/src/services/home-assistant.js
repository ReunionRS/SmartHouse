import WebSocket from 'ws';
import { pool } from '../db.js';
import { decryptToken } from '../lib/token-crypto.js';

export const getConnection = async (userId) => {
  const { rows } = await pool.query(
    'SELECT * FROM home_assistant_connections WHERE user_id = $1 LIMIT 1',
    [userId],
  );
  if (!rows.length) return null;
  return {
    ...rows[0],
    accessToken: decryptToken(rows[0].access_token_encrypted),
    refreshToken: decryptToken(rows[0].refresh_token_encrypted),
  };
};

export const haRest = async (userId, path, options = {}) => {
  const connection = await getConnection(userId);
  if (!connection) throw Object.assign(new Error('Home Assistant не подключён'), { statusCode: 409 });
  const response = await fetch(`${connection.base_url}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${connection.accessToken}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
    signal: AbortSignal.timeout(15000),
  });
  const body = await response.json().catch(() => null);
  if (!response.ok) {
    throw Object.assign(new Error(body?.message || 'Ошибка Home Assistant'), {
      statusCode: response.status,
    });
  }
  return body;
};

export const haWebSocket = async (userId, command) => {
  const connection = await getConnection(userId);
  if (!connection) throw Object.assign(new Error('Home Assistant не подключён'), { statusCode: 409 });
  const wsUrl = connection.base_url.replace(/^http/, 'ws') + '/api/websocket';
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(wsUrl, { handshakeTimeout: 10000 });
    const timeout = setTimeout(() => {
      socket.terminate();
      reject(Object.assign(new Error('Home Assistant не отвечает'), { statusCode: 504 }));
    }, 15000);
    const fail = (error) => {
      clearTimeout(timeout);
      socket.close();
      reject(error);
    };
    socket.on('error', fail);
    socket.on('message', (raw) => {
      const message = JSON.parse(raw.toString());
      if (message.type === 'auth_required') {
        socket.send(JSON.stringify({ type: 'auth', access_token: connection.accessToken }));
      } else if (message.type === 'auth_invalid') {
        fail(Object.assign(new Error('Авторизация Home Assistant устарела'), { statusCode: 401 }));
      } else if (message.type === 'auth_ok') {
        socket.send(JSON.stringify({ id: 1, ...command }));
      } else if (message.id === 1) {
        clearTimeout(timeout);
        socket.close();
        if (message.success) resolve(message.result);
        else reject(Object.assign(new Error(message.error?.message || 'Ошибка Home Assistant'), { statusCode: 502 }));
      }
    });
  });
};
