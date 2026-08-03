import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'crypto';
import { config } from '../config.js';

const key = createHash('sha256').update(config.tokenEncryptionKey).digest();

export const encryptToken = (plainText) => {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([cipher.update(plainText, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${iv.toString('base64')}.${tag.toString('base64')}.${encrypted.toString('base64')}`;
};

export const decryptToken = (payload) => {
  const [ivRaw, tagRaw, dataRaw] = String(payload || '').split('.');
  if (!ivRaw || !tagRaw || !dataRaw) throw new Error('Invalid encrypted token');
  const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(ivRaw, 'base64'));
  decipher.setAuthTag(Buffer.from(tagRaw, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(dataRaw, 'base64')),
    decipher.final(),
  ]).toString('utf8');
};
