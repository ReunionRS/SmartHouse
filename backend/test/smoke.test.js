import assert from 'node:assert/strict';
import test from 'node:test';
import { createApp } from '../src/app.js';
import { decryptToken, encryptToken } from '../src/lib/token-crypto.js';

test('health endpoint identifies Smart House API', async () => {
  const server = createApp().listen(0);
  try {
    const { port } = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/api/health`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      ok: true,
      service: 'smart-house-api',
    });
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('Home Assistant tokens are encrypted at rest', () => {
  const token = 'sensitive-ha-token';
  const encrypted = encryptToken(token);
  assert.notEqual(encrypted, token);
  assert.equal(decryptToken(encrypted), token);
});
