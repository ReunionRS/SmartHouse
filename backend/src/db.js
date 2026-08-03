import fs from 'fs/promises';
import { fileURLToPath } from 'url';
import { Pool } from 'pg';
import { config } from './config.js';

export const pool = new Pool({ connectionString: config.databaseUrl });

export const bootstrapDatabase = async () => {
  const schemaUrl = new URL('./schema.sql', import.meta.url);
  const schema = await fs.readFile(fileURLToPath(schemaUrl), 'utf8');
  await pool.query(schema);
};
