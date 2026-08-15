export const HOME_MODES = Object.freeze({
  HOME: 'HOME',
  AWAY: 'AWAY',
  NIGHT: 'NIGHT',
  VACATION: 'VACATION',
});

export const PRESET_SCENES = Object.freeze([
  { id: 'preset_home', name: 'Я дома', icon: 'home', description: 'Возвращает дом в обычный режим', mode: HOME_MODES.HOME },
  { id: 'preset_away', name: 'Я ушёл', icon: 'directions_walk', description: 'Выключает свет и безопасные розетки', mode: HOME_MODES.AWAY },
  { id: 'preset_morning', name: 'Доброе утро', icon: 'wb_sunny', description: 'Мягко включает основной свет', mode: HOME_MODES.HOME },
  { id: 'preset_night', name: 'Спокойной ночи', icon: 'bedtime', description: 'Оставляет только ночное освещение', mode: HOME_MODES.NIGHT },
  { id: 'preset_movie', name: 'Кино', icon: 'movie', description: 'Приглушает свет и включает медиазону', mode: HOME_MODES.HOME },
  { id: 'preset_vacation', name: 'Отпуск', icon: 'flight_takeoff', description: 'Переводит дом в безопасный длительный режим', mode: HOME_MODES.VACATION },
]);

export const findPreset = (id) => PRESET_SCENES.find((item) => item.id === id);

const action = (selector, service, data = {}, options = {}) => ({ selector, service, data, ...options });

export const buildPresetActions = (presetId, settings = {}) => {
  const brightness = (value, fallback) => Math.max(1, Math.min(255, Number(value ?? fallback)));
  switch (presetId) {
    case 'preset_home':
      return [action({ domain: 'light', tagsAny: ['primary_light'] }, 'turn_on', { brightness: brightness(settings.brightness, 180) }, { optional: true })];
    case 'preset_away':
      return [
        ...(settings.turnOffLights === false ? [] : [action({ domain: 'light' }, 'turn_off', {}, { optional: true })]),
        ...(settings.turnOffSockets === false ? [] : [action({ domain: 'switch', tagsAny: ['high_power'], tagsNone: ['protected', 'standby_allowed'] }, 'turn_off', {}, { optional: true })]),
        ...(settings.lockDoor === false ? [] : [action({ domain: 'lock', tagsAny: ['entrance_lock'] }, 'lock', {}, { optional: true, confirmation: true })]),
      ];
    case 'preset_morning':
      return [action({ domain: 'light', tagsAny: ['primary_light'] }, 'turn_on', { brightness: brightness(settings.brightness, 180) }, { optional: true })];
    case 'preset_night':
      return [
        action({ domain: 'light', tagsNone: ['night_light'] }, 'turn_off', {}, { optional: true }),
        action({ domain: 'light', tagsAny: ['night_light'] }, 'turn_on', { brightness: brightness(settings.nightBrightness, 35) }, { optional: true }),
        action({ domain: 'lock', tagsAny: ['entrance_lock'] }, 'lock', {}, { optional: true, confirmation: true }),
      ];
    case 'preset_movie':
      return [
        action({ domain: 'light', tagsAny: ['primary_light'] }, 'turn_off', {}, { optional: true }),
        action({ domain: 'light', tagsAny: ['ambient_light'] }, 'turn_on', { brightness: brightness(settings.brightness, 45) }, { optional: true }),
        action({ domain: 'media_player', tagsAny: ['media'] }, 'turn_on', {}, { optional: true }),
      ];
    case 'preset_vacation':
      return [
        action({ domain: 'light' }, 'turn_off', {}, { optional: true }),
        action({ domain: 'switch', tagsNone: ['protected', 'standby_allowed'] }, 'turn_off', {}, { optional: true }),
        action({ domain: 'climate', tagsAny: ['heating'] }, 'set_temperature', { temperature: Number(settings.temperature ?? 16) }, { optional: true }),
        action({ domain: 'lock', tagsAny: ['entrance_lock'] }, 'lock', {}, { optional: true, confirmation: true }),
      ];
    default:
      return [];
  }
};
