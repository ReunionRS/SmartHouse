import { haRest } from '../../services/home-assistant.js';
import { loadHomeSnapshot } from '../ha-context.js';
import { isBattery, isOpening, numericState } from '../home-assistant-normalizer.js';
import { getPublicWeather } from '../public-data/weather-service.js';

const functionTool = (name, description, properties = {}, required = []) => ({
  type: 'function',
  function: { name, description, parameters: { type: 'object', properties, required } },
});
const stringArg = (description) => ({ type: 'string', description });

export const aiToolDefinitions = [
  functionTool('get_weather', 'Получить актуальную погоду из разрешённого публичного источника', {
    location: stringArg('Название города или населённого пункта'),
  }, ['location']),
  functionTool('get_home_summary', 'Получить компактную актуальную сводку дома'),
  functionTool('get_rooms', 'Получить комнаты дома'),
  functionTool('get_devices', 'Получить устройства с необязательным фильтром по domain или комнате', {
    domain: stringArg('Необязательный HA domain, например light или sensor'),
    room: stringArg('Необязательное название или id комнаты'),
  }),
  functionTool('get_room_state', 'Получить актуальные устройства и датчики комнаты',
    { room: stringArg('Название или id комнаты') }, ['room']),
  functionTool('get_device_state', 'Получить актуальное состояние устройства',
    { device: stringArg('Понятное название или entity id устройства') }, ['device']),
  functionTool('get_lights_state', 'Получить список источников света и их состояния'),
  functionTool('get_openings_state', 'Получить открытые и закрытые двери, окна и другие проёмы'),
  functionTool('get_low_battery_devices', 'Получить устройства с низким зарядом',
    { threshold: { type: 'number', description: 'Порог процентов от 1 до 100' } }),
  functionTool('get_unavailable_devices', 'Получить недоступные устройства'),
  functionTool('get_temperature', 'Получить фактическую температуру в комнате',
    { room: stringArg('Название или id комнаты') }, ['room']),
  functionTool('get_humidity', 'Получить фактическую влажность в комнате',
    { room: stringArg('Название или id комнаты') }, ['room']),
  functionTool('get_energy_usage', 'Получить доступные показатели энергии и мощности'),
  functionTool('get_device_history', 'Получить компактную историю состояния устройства', {
    device: stringArg('Название или entity id устройства'),
    period: stringArg('Период: 1h, 6h, 12h, 24h или 7d'),
  }, ['device', 'period']),
  functionTool('get_events', 'Получить последние события Home Assistant', {
    period: stringArg('Период: 1h, 6h, 12h, 24h или 7d'),
  }, ['period']),
  functionTool('turn_on_device', 'Включить разрешённый свет или выключатель',
    { device: stringArg('Название или entity id устройства') }, ['device']),
  functionTool('turn_off_device', 'Выключить разрешённый свет или выключатель',
    { device: stringArg('Название или entity id устройства') }, ['device']),
  functionTool('set_light_brightness', 'Установить яркость света в процентах', {
    device: stringArg('Название или entity id источника света'),
    brightness_percent: { type: 'number', minimum: 1, maximum: 100 },
  }, ['device', 'brightness_percent']),
  functionTool('run_scene', 'Запустить существующую сцену',
    { scene: stringArg('Название или entity id сцены') }, ['scene']),
  functionTool('set_climate_temperature', 'Изменить целевую температуру; большое изменение требует подтверждения', {
    device: stringArg('Название или entity id климатического устройства'),
    temperature: { type: 'number', minimum: 5, maximum: 35 },
  }, ['device', 'temperature']),
  functionTool('open_cover', 'Открыть обычные шторы или другой безопасный cover',
    { device: stringArg('Название или entity id cover') }, ['device']),
  functionTool('close_cover', 'Закрыть обычные шторы или другой безопасный cover',
    { device: stringArg('Название или entity id cover') }, ['device']),
  functionTool('prepare_automation_draft', 'Подготовить черновик автоматизации без сохранения', {
    name: stringArg('Название'),
    description: stringArg('Краткое описание логики'),
    trigger_device: stringArg('Название или entity id датчика-триггера'),
    trigger_state: { type: 'string', enum: ['on', 'off'], description: 'Состояние запуска' },
    action_devices: { type: 'array', items: { type: 'string' }, description: 'Названия или entity id устройств действия' },
    action: { type: 'string', enum: ['turn_on', 'turn_off', 'flash'], description: 'Безопасное действие' },
  }, ['name', 'description', 'trigger_device', 'trigger_state', 'action_devices', 'action']),
];

const comparable = (value) => String(value || '').trim().toLocaleLowerCase('ru-RU');
const periodRange = (raw) => {
  const allowed = { '1h': 1, '6h': 6, '12h': 12, '24h': 24, '7d': 168 };
  const period = Object.hasOwn(allowed, raw) ? raw : '12h';
  const end = new Date();
  return { period, from: new Date(end.getTime() - allowed[period] * 3600000), end };
};
const findRoom = (rooms, query) => {
  const wanted = comparable(query);
  const stem = wanted.slice(0, Math.min(5, wanted.length));
  return rooms.find((item) => {
    const id = comparable(item.id);
    const name = comparable(item.name);
    return id === wanted || name === wanted || (stem.length >= 4 && (id.startsWith(stem) || name.startsWith(stem)));
  });
};
export const requiresClimateConfirmation = (current, requested) =>
  !Number.isFinite(Number(current)) || Math.abs(Number(requested) - Number(current)) > 3;
const physicalSensorClasses = new Set([
  'temperature', 'humidity', 'battery', 'power', 'energy', 'current',
  'voltage', 'moisture', 'illuminance', 'pressure', 'gas', 'carbon_monoxide',
  'carbon_dioxide', 'pm1', 'pm10', 'pm25', 'signal_strength', 'aqi',
  'door', 'window', 'opening', 'motion', 'occupancy', 'smoke', 'sound',
  'vibration', 'water', 'problem', 'safety', 'lock', 'garage_door',
]);
const isPhysicalEntity = (entity) => {
  if (!['sensor', 'binary_sensor'].includes(entity.domain)) return true;
  return physicalSensorClasses.has(String(entity.attributes.device_class || ''));
};
const resolveOne = (entities, query, domains) => {
  const wanted = comparable(query);
  const candidates = entities.filter((item) => domains.includes(item.domain));
  const exact = candidates.filter((item) => comparable(item.entity_id) === wanted || comparable(item.name) === wanted);
  const matches = exact.length ? exact : candidates.filter((item) => comparable(item.name).includes(wanted));
  if (!matches.length) return { error: 'DEVICE_NOT_FOUND' };
  if (matches.length > 1) return { error: 'AMBIGUOUS_DEVICE', matches: matches.map((item) => item.name) };
  return { entity: matches[0] };
};

const callAndConfirm = async (userId, entity, service, data = {}) => {
  await haRest(userId, `/api/services/${entity.domain}/${service}`, {
    method: 'POST', body: JSON.stringify({ entity_id: entity.entity_id, ...data }),
  });
  if (entity.domain === 'scene') return { success: true, device: entity.name, command_sent: true };
  const state = await haRest(userId, `/api/states/${entity.entity_id}`);
  const newState = String(state.state || 'unknown');
  const expected = service === 'turn_off' ? 'off' : 'on';
  return {
    success: newState === expected,
    command_sent: true,
    device: entity.name,
    new_state: newState,
    ...(newState !== expected ? { warning: 'Home Assistant пока не подтвердил новое состояние' } : {}),
  };
};

export const executeAiTool = async ({ userId, name, args = {}, confirmed = false }) => {
  if (name === 'get_weather') return getPublicWeather(args.location);
  const snapshot = await loadHomeSnapshot(userId);
  const { entities, rooms } = snapshot;
  const physicalDomains = new Set([
    'light', 'switch', 'sensor', 'binary_sensor', 'climate', 'cover',
    'lock', 'fan', 'camera', 'media_player', 'vacuum', 'water_heater',
  ]);
  const physicalEntities = entities.filter((item) =>
    physicalDomains.has(item.domain) && isPhysicalEntity(item));
  if (name === 'get_rooms') return { rooms };
  if (name === 'get_devices') {
    const room = args.room ? findRoom(rooms, args.room) : null;
    if (args.room && !room) return { error: 'ROOM_NOT_FOUND' };
    const domain = comparable(args.domain);
    return {
      devices: physicalEntities.filter((item) =>
        (!domain || item.domain === domain) && (!room || item.room_id === room.id)),
    };
  }
  if (name === 'get_lights_state') return { lights: entities.filter((item) => item.domain === 'light') };
  if (name === 'get_openings_state') return { openings: entities.filter(isOpening) };
  if (name === 'get_unavailable_devices') return { devices: physicalEntities.filter((item) => !item.available) };
  if (name === 'get_low_battery_devices') {
    const threshold = Math.min(100, Math.max(1, Number(args.threshold || 20)));
    const batteryDevices = entities.filter(isBattery)
      .map((item) => ({ ...item, battery: numericState(item) }));
    const measuredDevices = batteryDevices.filter((item) => item.battery != null);
    return {
      status: physicalEntities.length === 0
        ? 'no_devices'
        : measuredDevices.length === 0
          ? 'no_battery_data'
          : 'ok',
      threshold,
      total_home_entities: physicalEntities.length,
      total_battery_devices: batteryDevices.length,
      measured_battery_devices: measuredDevices.length,
      devices: measuredDevices.filter((item) => item.battery <= threshold),
    };
  }
  if (name === 'get_temperature' || name === 'get_humidity') {
    const room = findRoom(rooms, args.room);
    if (!room) return { error: 'ROOM_NOT_FOUND' };
    const deviceClass = name === 'get_temperature' ? 'temperature' : 'humidity';
    const measurements = entities
      .filter((item) => item.room_id === room.id && item.attributes.device_class === deviceClass)
      .map((item) => ({ name: item.name, value: numericState(item), unit: item.attributes.unit_of_measurement || (deviceClass === 'temperature' ? '°C' : '%') }))
      .filter((item) => item.value != null);
    return { room, status: measurements.length ? 'ok' : 'no_data', measurements };
  }
  if (name === 'get_energy_usage') {
    const measurements = entities
      .filter((item) => ['energy', 'power'].includes(item.attributes.device_class))
      .map((item) => ({ name: item.name, room: item.room_name, type: item.attributes.device_class, value: numericState(item), unit: item.attributes.unit_of_measurement || '' }))
      .filter((item) => item.value != null);
    return { status: measurements.length ? 'ok' : 'no_data', measurements };
  }
  if (name === 'get_room_state') {
    const room = findRoom(rooms, args.room);
    if (!room) return { error: 'ROOM_NOT_FOUND' };
    return { room, devices: entities.filter((item) => item.room_id === room.id) };
  }
  if (name === 'get_device_history') {
    const resolved = resolveOne(entities, args.device, [...physicalDomains]);
    if (resolved.error) return resolved;
    const range = periodRange(String(args.period || '12h'));
    const query = new URLSearchParams({
      filter_entity_id: resolved.entity.entity_id,
      end_time: range.end.toISOString(),
      minimal_response: '',
      no_attributes: '',
    });
    const raw = await haRest(userId, `/api/history/period/${encodeURIComponent(range.from.toISOString())}?${query}`);
    const states = Array.isArray(raw?.[0]) ? raw[0] : [];
    return {
      device: { name: resolved.entity.name, room: resolved.entity.room_name },
      period: range.period,
      events: states.slice(-200).map((item) => ({ time: item.last_changed || item.last_updated || '', state: String(item.state ?? '') })),
    };
  }
  if (name === 'get_events') {
    const range = periodRange(String(args.period || '12h'));
    const query = new URLSearchParams({ end_time: range.end.toISOString() });
    const raw = await haRest(userId, `/api/logbook/${encodeURIComponent(range.from.toISOString())}?${query}`);
    return {
      period: range.period,
      events: (Array.isArray(raw) ? raw : []).slice(-200).map((item) => ({
        time: item.when || '', name: item.name || '', message: item.message || '', state: item.state || '',
      })),
    };
  }
  if (name === 'get_home_summary') {
    const temperatures = entities.filter((item) => item.attributes.device_class === 'temperature').map(numericState).filter((v) => v != null);
    const humidity = entities.filter((item) => item.attributes.device_class === 'humidity').map(numericState).filter((v) => v != null);
    const lights = entities.filter((item) => item.domain === 'light');
    return {
      home_status: physicalEntities.length === 0
        ? 'no_devices'
        : physicalEntities.some((item) => !item.available)
          ? 'attention'
          : 'ok',
      device_count: physicalEntities.length,
      temperature: temperatures.length ? { average: +(temperatures.reduce((a, b) => a + b, 0) / temperatures.length).toFixed(1), min: Math.min(...temperatures), max: Math.max(...temperatures) } : null,
      humidity: humidity.length ? { average: +(humidity.reduce((a, b) => a + b, 0) / humidity.length).toFixed(0) } : null,
      lights: { on: lights.filter((item) => item.state === 'on').length, total: lights.length },
      openings: { open: entities.filter((item) => isOpening(item) && ['on', 'open'].includes(item.state)).map((item) => ({ name: item.name, room: item.room_name })) },
      low_battery: entities.filter(isBattery).map((item) => ({ name: item.name, battery: numericState(item) })).filter((item) => item.battery != null && item.battery <= 20),
      unavailable_devices: physicalEntities.filter((item) => !item.available).length,
      home_assistant_online: true,
    };
  }
  if (name === 'get_device_state') return resolveOne(entities, args.device, ['light', 'switch', 'sensor', 'binary_sensor', 'climate', 'cover', 'scene']);
  if (name === 'prepare_automation_draft') {
    const trigger = resolveOne(physicalEntities, args.trigger_device, ['binary_sensor', 'sensor']);
    if (trigger.error) return { ...trigger, field: 'trigger_device' };
    const requestedActions = Array.isArray(args.action_devices) ? args.action_devices.slice(0, 20) : [];
    if (!requestedActions.length) return { error: 'DEVICE_NOT_FOUND', field: 'action_devices' };
    const actionDevices = [];
    for (const requested of requestedActions) {
      const resolvedAction = resolveOne(physicalEntities, requested, ['light', 'switch']);
      if (resolvedAction.error) return { ...resolvedAction, field: 'action_devices', requested };
      actionDevices.push({
        entity_id: resolvedAction.entity.entity_id,
        name: resolvedAction.entity.name,
        domain: resolvedAction.entity.domain,
      });
    }
    const action = ['turn_on', 'turn_off', 'flash'].includes(args.action) ? args.action : 'turn_on';
    if (action === 'flash' && actionDevices.some((item) => item.domain !== 'light')) {
      return { error: 'ACTION_NOT_SUPPORTED', message: 'Мигание доступно только для ламп' };
    }
    return {
      type: 'automation_draft',
      draft: {
        name: String(args.name || '').slice(0, 100),
        description: String(args.description || '').slice(0, 1000),
        trigger: {
          entity_id: trigger.entity.entity_id,
          name: trigger.entity.name,
          state: args.trigger_state === 'off' ? 'off' : 'on',
        },
        actions: actionDevices.map((item) => ({ ...item, action })),
        status: 'draft',
      },
    };
  }
  const domains = name === 'run_scene'
    ? ['scene']
    : name === 'set_light_brightness'
      ? ['light']
      : name === 'set_climate_temperature'
        ? ['climate']
        : ['open_cover', 'close_cover'].includes(name)
          ? ['cover']
          : ['light', 'switch'];
  const target = args.device || args.scene;
  const resolved = resolveOne(entities, target, domains);
  if (resolved.error) return resolved;
  if (!resolved.entity.available) return { error: 'DEVICE_UNAVAILABLE', device: resolved.entity.name };
  if (name === 'set_climate_temperature' && !confirmed) {
    const requested = Math.min(35, Math.max(5, Number(args.temperature)));
    const current = Number(resolved.entity.attributes.temperature ?? resolved.entity.attributes.current_temperature);
    if (requiresClimateConfirmation(current, requested)) {
      return {
        requires_confirmation: true,
        action: { tool: name, args: { ...args, temperature: requested } },
        reason: 'significant_temperature_change',
      };
    }
  }
  if (name === 'turn_on_device') return callAndConfirm(userId, resolved.entity, 'turn_on');
  if (name === 'turn_off_device') return callAndConfirm(userId, resolved.entity, 'turn_off');
  if (name === 'set_light_brightness') {
    const percent = Math.min(100, Math.max(1, Number(args.brightness_percent)));
    return callAndConfirm(userId, resolved.entity, 'turn_on', { brightness_pct: percent });
  }
  if (name === 'run_scene') return callAndConfirm(userId, resolved.entity, 'turn_on');
  if (name === 'set_climate_temperature') {
    const temperature = Math.min(35, Math.max(5, Number(args.temperature)));
    await haRest(userId, '/api/services/climate/set_temperature', {
      method: 'POST',
      body: JSON.stringify({ entity_id: resolved.entity.entity_id, temperature }),
    });
    return { success: true, command_sent: true, device: resolved.entity.name, temperature };
  }
  if (name === 'open_cover' || name === 'close_cover') {
    const service = name === 'open_cover' ? 'open_cover' : 'close_cover';
    await haRest(userId, `/api/services/cover/${service}`, {
      method: 'POST',
      body: JSON.stringify({ entity_id: resolved.entity.entity_id }),
    });
    const state = await haRest(userId, `/api/states/${resolved.entity.entity_id}`);
    const expected = name === 'open_cover' ? 'open' : 'closed';
    return {
      success: state.state === expected,
      command_sent: true,
      device: resolved.entity.name,
      new_state: state.state,
      ...(state.state !== expected
          ? { warning: 'Home Assistant пока не подтвердил новое состояние' }
          : {}),
    };
  }
  return { error: 'ACTION_NOT_SUPPORTED' };
};
