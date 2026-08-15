const inferredTags = (entity) => {
  const value = `${entity.entity_id} ${entity.name} ${entity.attributes?.device_class || ''}`.toLowerCase();
  const tags = new Set(entity.tags || []);
  if (entity.domain === 'light') tags.add('primary_light');
  if (/night|ночн/.test(value)) tags.add('night_light');
  if (/ambient|rgb|подсвет/.test(value)) tags.add('ambient_light');
  if (entity.domain === 'media_player') tags.add('media');
  if (entity.domain === 'climate') tags.add('heating');
  if (entity.domain === 'lock' && /entrance|front|вход/.test(value)) tags.add('entrance_lock');
  if (entity.domain === 'switch' && /heater|oven|kettle|утюг|обогрев|чайник/.test(value)) tags.add('high_power');
  if (['smoke', 'gas', 'moisture'].includes(entity.attributes?.device_class)) tags.add('critical_sensor');
  return [...tags];
};

export const decorateEntities = (entities, tagMap = {}) => entities.map((entity) => ({
  ...entity,
  tags: [...new Set([...inferredTags(entity), ...(tagMap[entity.entity_id] || [])])],
}));

export const resolveDevices = (entities, selector) => entities.filter((entity) => {
  if (selector.domain && entity.domain !== selector.domain) return false;
  if (selector.roomId && entity.room_id !== selector.roomId) return false;
  if (selector.capability && !entity.capabilities?.includes(selector.capability)) return false;
  if (selector.tagsAny?.length && !selector.tagsAny.some((tag) => entity.tags?.includes(tag))) return false;
  if (selector.tagsNone?.some((tag) => entity.tags?.includes(tag))) return false;
  return true;
});
