const usefulAttributes = Object.freeze({
  light: ['brightness', 'color_temp_kelvin', 'rgb_color', 'supported_color_modes'],
  climate: ['current_temperature', 'temperature', 'humidity', 'hvac_action'],
  sensor: ['device_class', 'unit_of_measurement', 'state_class', 'battery_level'],
  binary_sensor: ['device_class', 'battery_level'],
  cover: ['current_position', 'device_class'],
  switch: ['device_class'],
  scene: [],
});

const copyWhitelistedAttributes = (domain, attributes) => Object.fromEntries(
  (usefulAttributes[domain] || []).filter((key) => attributes[key] != null)
    .map((key) => [key, attributes[key]]),
);

export const normalizeEntity = (state, metadata = {}) => {
  const entityId = String(state?.entity_id || metadata.entity_id || '');
  const domain = entityId.split('.')[0];
  const attributes = state?.attributes || {};
  const rawState = String(state?.state ?? 'unknown');
  return {
    id: metadata.id || entityId,
    entity_id: entityId,
    name: String(metadata.name || metadata.original_name || attributes.friendly_name || entityId),
    room_id: metadata.area_id || '',
    room_name: metadata.room_name || '',
    domain,
    state: rawState,
    available: !['unavailable', 'unknown'].includes(rawState),
    attributes: copyWhitelistedAttributes(domain, attributes),
    capabilities: domain === 'light'
      ? ['turn_on', 'turn_off', ...(attributes.brightness != null ? ['brightness'] : [])]
      : ['turn_on', 'turn_off'].filter(() => ['switch'].includes(domain)),
    last_changed: state?.last_changed || '',
    last_updated: state?.last_updated || '',
  };
};

export const isOpening = (entity) => entity.domain === 'cover'
  || (entity.domain === 'binary_sensor'
    && ['door', 'window', 'opening', 'garage_door'].includes(entity.attributes.device_class));

export const isBattery = (entity) => entity.domain === 'sensor'
  && (entity.attributes.device_class === 'battery'
    || String(entity.name).toLowerCase().includes('battery')
    || String(entity.name).toLowerCase().includes('заряд'));

export const numericState = (entity) => {
  const value = Number.parseFloat(entity.state);
  return Number.isFinite(value) ? value : null;
};
