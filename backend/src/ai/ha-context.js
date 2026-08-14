import { haRest, haWebSocket } from '../services/home-assistant.js';
import { normalizeEntity } from './home-assistant-normalizer.js';

const safeRegistry = async (userId, type) => {
  try { return await haWebSocket(userId, { type }); } catch { return []; }
};

export const loadHomeSnapshot = async (userId) => {
  const [states, areas, devices, registry] = await Promise.all([
    haRest(userId, '/api/states'),
    safeRegistry(userId, 'config/area_registry/list'),
    safeRegistry(userId, 'config/device_registry/list'),
    safeRegistry(userId, 'config/entity_registry/list'),
  ]);
  const deviceAreas = new Map(devices.map((item) => [item.id, item.area_id || '']));
  const areaNames = new Map(areas.map((item) => [item.area_id || item.id, item.name || '']));
  const metadata = new Map(registry.map((item) => {
    const areaId = item.area_id || deviceAreas.get(item.device_id) || '';
    return [item.entity_id, { ...item, area_id: areaId, room_name: areaNames.get(areaId) || '' }];
  }));
  return {
    rooms: areas.map((item) => ({ id: item.area_id || item.id, name: item.name || '' })),
    entities: states.map((state) => normalizeEntity(state, metadata.get(state.entity_id))),
  };
};
