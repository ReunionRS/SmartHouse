import 'dotenv/config';

const isProduction = process.env.NODE_ENV === 'production';
const jwtSecret = process.env.JWT_SECRET || (isProduction ? '' : 'smart-house-local-dev');
if (!jwtSecret) throw new Error('JWT_SECRET is required in production');

export const config = Object.freeze({
  port: Number(process.env.PORT || 4000),
  databaseUrl:
    process.env.DATABASE_URL ||
    'postgresql://postgres:postgres@localhost:5432/smart_house',
  jwtSecret,
  tokenEncryptionKey: process.env.TOKEN_ENCRYPTION_KEY || jwtSecret,
  corsOrigins: (process.env.CORS_ORIGIN || 'http://localhost:5173')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean),
  uploadsDir: new URL('../uploads/', import.meta.url),
  haWebAppUrl: process.env.HA_WEB_APP_URL || '',
  haInternalBaseUrl: process.env.HA_INTERNAL_BASE_URL || '',
  haWebRedirectUris: (process.env.HA_WEB_REDIRECT_URIS || '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean),
  haPairingSecret:
    process.env.HA_PAIRING_SECRET ||
    (isProduction ? '' : 'smart-house-local-pairing-secret-change-me'),
  ai: Object.freeze({
    enabled: process.env.AI_ENABLED !== 'false',
    provider: process.env.AI_PROVIDER || 'ollama',
    baseUrl: process.env.QWEN_BASE_URL || 'http://localhost:11434',
    apiKey: process.env.QWEN_API_KEY || '',
    model: process.env.QWEN_MODEL || 'qwen2.5:7b',
    maxToolRounds: Math.min(8, Math.max(1, Number(process.env.AI_MAX_TOOL_ROUNDS || 6))),
    timeoutMs: Math.min(180000, Math.max(5000, Number(process.env.AI_TIMEOUT_MS || 120000))),
    confirmationTtlSeconds: Math.max(30, Number(process.env.AI_CONFIRMATION_TTL_SECONDS || 120)),
  }),
});

if (!config.haPairingSecret) {
  throw new Error('HA_PAIRING_SECRET is required in production');
}
