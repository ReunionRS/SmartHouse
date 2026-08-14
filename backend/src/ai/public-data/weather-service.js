const geocodingEndpoint = 'https://geocoding-api.open-meteo.com/v1/search';
const forecastEndpoint = 'https://api.open-meteo.com/v1/forecast';

const russianLocationAliases = new Map([
  ['казани', 'Казань'],
  ['москве', 'Москва'],
  ['самаре', 'Самара'],
  ['уфе', 'Уфа'],
  ['ижевске', 'Ижевск'],
  ['петербурге', 'Санкт-Петербург'],
  ['санкт-петербурге', 'Санкт-Петербург'],
]);

const weatherDescription = (code) => {
  if (code === 0) return 'ясно';
  if ([1, 2].includes(code)) return 'переменная облачность';
  if (code === 3) return 'пасмурно';
  if ([45, 48].includes(code)) return 'туман';
  if ([51, 53, 55, 56, 57].includes(code)) return 'морось';
  if ([61, 63, 65, 66, 67, 80, 81, 82].includes(code)) return 'дождь';
  if ([71, 73, 75, 77, 85, 86].includes(code)) return 'снег';
  if ([95, 96, 99].includes(code)) return 'гроза';
  return 'погодные условия не определены';
};

const requestJson = async (url, fetchImpl) => {
  const response = await fetchImpl(url, {
    headers: { Accept: 'application/json', 'User-Agent': 'SmartHouse-Hub/1.0' },
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) throw new Error(`PUBLIC_DATA_HTTP_${response.status}`);
  return response.json();
};

export const getPublicWeather = async (rawLocation, { fetchImpl = fetch } = {}) => {
  const requested = String(rawLocation || '').trim().slice(0, 100);
  if (requested.length < 2) return { error: 'LOCATION_REQUIRED' };
  const withoutPlacePrefix = requested
    .replace(/^(?:жк|жилой\s+комплекс|район|микрорайон|мкр\.?)\s+/iu, '')
    .trim();
  const normalized = russianLocationAliases.get(
    withoutPlacePrefix.toLocaleLowerCase('ru-RU'),
  ) || withoutPlacePrefix;
  const candidates = [normalized];
  if (/ках$/iu.test(normalized)) {
    candidates.push(normalized.replace(/ах$/iu, 'и'));
  } else if (/[кгх]е$/iu.test(normalized)) {
    candidates.push(normalized.slice(0, -1));
  }
  let place;
  for (const candidate of [...new Set(candidates)]) {
    const geocodingUrl = new URL(geocodingEndpoint);
    geocodingUrl.search = new URLSearchParams({
      name: candidate,
      count: '1',
      language: 'ru',
      format: 'json',
    });
    const geocoding = await requestJson(geocodingUrl, fetchImpl);
    place = geocoding?.results?.[0];
    if (place) break;
  }
  if (!place) return { error: 'LOCATION_NOT_FOUND', requested_location: requested };

  const forecastUrl = new URL(forecastEndpoint);
  forecastUrl.search = new URLSearchParams({
    latitude: String(place.latitude),
    longitude: String(place.longitude),
    current: [
      'temperature_2m',
      'apparent_temperature',
      'relative_humidity_2m',
      'precipitation',
      'weather_code',
      'wind_speed_10m',
    ].join(','),
    timezone: 'auto',
  });
  const forecast = await requestJson(forecastUrl, fetchImpl);
  const current = forecast?.current;
  if (!current) throw new Error('PUBLIC_DATA_INVALID_RESPONSE');

  return {
    status: 'ok',
    location: {
      name: place.name,
      region: place.admin1 || '',
      country: place.country || '',
    },
    observed_at: current.time,
    weather: weatherDescription(Number(current.weather_code)),
    temperature_c: current.temperature_2m,
    feels_like_c: current.apparent_temperature,
    humidity_percent: current.relative_humidity_2m,
    precipitation_mm: current.precipitation,
    wind_kmh: current.wind_speed_10m,
    source: 'Open-Meteo',
    source_url: 'https://open-meteo.com/',
  };
};
