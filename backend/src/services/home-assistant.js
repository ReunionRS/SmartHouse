import WebSocket from 'ws';
import { pool } from '../db.js';
import { decryptToken, encryptToken } from '../lib/token-crypto.js';
import { config } from '../config.js';

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

const refreshes = new Map();

const performRefresh = async (connection) => {
  const baseUrl = config.haInternalBaseUrl || connection.base_url;
  const response = await fetch(`${baseUrl}/auth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: connection.refreshToken,
      client_id: connection.client_id,
    }),
    signal: AbortSignal.timeout(15000),
  });
  const body = await response.json().catch(() => null);
  if (!response.ok || !body?.access_token) {
    throw Object.assign(new Error('Авторизация Home Assistant устарела'), { statusCode: 401 });
  }
  const expiresAt = new Date(Date.now() + Number(body.expires_in || 1800) * 1000);
  const refreshToken = body.refresh_token || connection.refreshToken;
  await pool.query(
    `UPDATE home_assistant_connections
     SET access_token_encrypted=$2, refresh_token_encrypted=$3, expires_at=$4, status='connected', updated_at=NOW()
     WHERE id=$1`,
    [connection.id, encryptToken(body.access_token), encryptToken(refreshToken), expiresAt],
  );
  return { ...connection, accessToken: body.access_token, refreshToken, expires_at: expiresAt };
};

const refreshConnection = async (connection) => {
  const existing = refreshes.get(connection.id);
  if (existing) return existing;
  const request = performRefresh(connection).finally(() => {
    refreshes.delete(connection.id);
  });
  refreshes.set(connection.id, request);
  return request;
};

const requestRest = async (connection, path, options) => {
  const baseUrl = config.haInternalBaseUrl || connection.base_url;
  return fetch(`${baseUrl}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${connection.accessToken}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
    signal: AbortSignal.timeout(15000),
  });
};

export const haRest = async (userId, path, options = {}) => {
  const connection = await getConnection(userId);
  if (!connection) throw Object.assign(new Error('Home Assistant не подключён'), { statusCode: 409 });
  let response = await requestRest(connection, path, options);
  if (response.status === 401 && connection.refreshToken) {
    const refreshed = await refreshConnection(connection);
    response = await requestRest(refreshed, path, options);
  }
  const body = await response.json().catch(() => null);
  if (!response.ok) {
    throw Object.assign(new Error(body?.message || 'Ошибка Home Assistant'), {
      statusCode: response.status,
    });
  }
  return body;
};

const webSocketRequest = async (connection, command) => {
  if (!connection) throw Object.assign(new Error('Home Assistant не подключён'), { statusCode: 409 });
  const wsUrl = (config.haInternalBaseUrl || connection.base_url).replace(/^http/, 'ws') + '/api/websocket';
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
        fail(Object.assign(new Error('Авторизация Home Assistant устарела'), { statusCode: 401, code: 'HA_AUTH_INVALID' }));
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

export const haWebSocket = async (userId, command) => {
  const connection = await getConnection(userId);
  try {
    return await webSocketRequest(connection, command);
  } catch (error) {
    if (error?.code !== 'HA_AUTH_INVALID' || !connection?.refreshToken) throw error;
    const refreshed = await refreshConnection(connection);
    return webSocketRequest(refreshed, command);
  }
};

const waitForStateWithConnection = (connection, entityId, expectedState, timeoutMs) => {
  if (!connection) throw Object.assign(new Error('Home Assistant не подключён'), { statusCode: 409 });
  const wsUrl = (config.haInternalBaseUrl || connection.base_url).replace(/^http/, 'ws') + '/api/websocket';
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(wsUrl, { handshakeTimeout: 10000 });
    let settled = false;
    const finish = (value, error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      socket.close();
      if (error) reject(error); else resolve(value);
    };
    const timeout = setTimeout(() => finish(false), timeoutMs);
    socket.on('error', (error) => finish(false, error));
    socket.on('message', (raw) => {
      const message = JSON.parse(raw.toString());
      if (message.type === 'auth_required') socket.send(JSON.stringify({ type: 'auth', access_token: connection.accessToken }));
      else if (message.type === 'auth_invalid') finish(false, Object.assign(new Error('Авторизация Home Assistant устарела'), { code: 'HA_AUTH_INVALID' }));
      else if (message.type === 'auth_ok') socket.send(JSON.stringify({ id: 1, type: 'subscribe_events', event_type: 'state_changed' }));
      else if (message.type === 'event' && message.event?.data?.entity_id === entityId
        && message.event?.data?.new_state?.state === expectedState) finish(true);
    });
  });
};

export const haWaitForState = async (userId, entityId, expectedState, timeoutMs = 5000) => {
  const connection = await getConnection(userId);
  try {
    return await waitForStateWithConnection(connection, entityId, expectedState, timeoutMs);
  } catch (error) {
    if (error?.code !== 'HA_AUTH_INVALID' || !connection?.refreshToken) throw error;
    return waitForStateWithConnection(await refreshConnection(connection), entityId, expectedState, timeoutMs);
  }
};
