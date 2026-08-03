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
  haWebRedirectUris: (process.env.HA_WEB_REDIRECT_URIS || '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean),
});
