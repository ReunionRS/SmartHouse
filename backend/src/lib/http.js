export const asyncRoute = (handler) => (req, res, next) =>
  Promise.resolve(handler(req, res, next)).catch(next);

export const normalizeBaseUrl = (value) => {
  const raw = String(value || '').trim().replace(/\/$/, '');
  const parsed = new URL(raw);
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw Object.assign(new Error('Поддерживаются только HTTP и HTTPS'), {
      statusCode: 400,
    });
  }
  return parsed.toString().replace(/\/$/, '');
};
