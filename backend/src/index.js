import { createApp } from './app.js';
import { config } from './config.js';
import { bootstrapDatabase, pool } from './db.js';

const start = async () => {
  await bootstrapDatabase();
  const app = createApp();
  const server = app.listen(config.port, () => {
    console.log(`Smart House API started on http://localhost:${config.port}`);
  });

  const shutdown = async () => {
    server.close();
    await pool.end();
  };
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
};

start().catch((error) => {
  console.error('Failed to start Smart House API', error);
  process.exit(1);
});
