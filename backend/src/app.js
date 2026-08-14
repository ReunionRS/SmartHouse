import cors from 'cors';
import express from 'express';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { config } from './config.js';
import authRoutes from './routes/auth.js';
import userRoutes from './routes/users.js';
import pushRoutes from './routes/push.js';
import haRoutes, { oauthRouter } from './routes/home-assistant.js';
import systemRoutes from './routes/systems.js';
import aiRoutes from './routes/ai.js';
import automationRoutes from './routes/automations.js';
import appStateRoutes from './routes/app-state.js';

const uploadsPath = fileURLToPath(config.uploadsDir);

export const createApp = () => {
  fs.mkdirSync(`${uploadsPath}/avatars`, { recursive: true });
  const app = express();
  app.disable('x-powered-by');
  app.use(cors({
    credentials: true,
    origin(origin, done) {
      if (!origin || config.corsOrigins.includes(origin)) return done(null, true);
      if (process.env.NODE_ENV !== 'production' && /^https?:\/\/(localhost|127\.0\.0\.1|192\.168\.|10\.)/.test(origin)) return done(null, true);
      done(new Error('Not allowed by CORS'));
    },
  }));
  app.use(express.json({ limit: '1mb' }));
  app.use('/uploads', express.static(uploadsPath, { fallthrough: false }));
  app.get('/api/health', (_req, res) => res.json({ ok: true, service: 'smart-house-api' }));
  app.use(oauthRouter);
  app.use('/api/auth', authRoutes);
  app.use('/api/users', userRoutes);
  app.use('/api/push', pushRoutes);
  app.use('/api/home-assistant', haRoutes);
  app.use('/api/systems', systemRoutes);
  app.use('/api/ai', aiRoutes);
  app.use('/api/automations', automationRoutes);
  app.use('/api/app-state', appStateRoutes);
  app.use((_req, res) => res.status(404).json({ error: 'Маршрут не найден' }));
  app.use((error, _req, res, _next) => {
    console.error(error);
    res.status(error.statusCode || 500).json({
      error: error.statusCode ? error.message : 'Внутренняя ошибка сервера',
      ...(error.code ? { code: error.code } : {}),
    });
  });
  return app;
};
