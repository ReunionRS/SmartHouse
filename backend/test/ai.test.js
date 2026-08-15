import assert from 'node:assert/strict';
import test from 'node:test';
import { isOpening, normalizeEntity } from '../src/ai/home-assistant-normalizer.js';
import { OllamaProvider } from '../src/ai/providers/ollama-provider.js';
import { requiresClimateConfirmation } from '../src/ai/tools/ai-tools.js';
import { exactToolResponse, inferAutomationTool, inferReadTool } from '../src/ai/ai-orchestrator.js';
import { AiOrchestrator } from '../src/ai/ai-orchestrator.js';
import { getPublicWeather } from '../src/ai/public-data/weather-service.js';
import { searchMarketplaces } from '../src/ai/public-data/marketplace-search-service.js';

test('HA entity normalization only exposes whitelisted attributes', () => {
  const entity = normalizeEntity({
    entity_id: 'binary_sensor.kitchen_window',
    state: 'on',
    attributes: {
      friendly_name: 'Окно кухни',
      device_class: 'window',
      secret: 'must-not-leak',
    },
  }, { area_id: 'kitchen', room_name: 'Кухня' });
  assert.equal(entity.name, 'Окно кухни');
  assert.equal(entity.room_name, 'Кухня');
  assert.equal(entity.attributes.secret, undefined);
  assert.equal(isOpening(entity), true);
});

test('Ollama provider sends tool-compatible chat request', async () => {
  let request;
  const provider = new OllamaProvider({
    baseUrl: 'http://ollama.local',
    model: 'qwen2.5:7b',
    fetchImpl: async (_url, options) => {
      request = JSON.parse(options.body);
      return {
        ok: true,
        json: async () => ({ message: { role: 'assistant', content: 'Готово' } }),
      };
    },
  });
  const result = await provider.chatWithTools(
    [{ role: 'user', content: 'Привет' }],
    [],
  );
  assert.equal(request.model, 'qwen2.5:7b');
  assert.equal(result.message.content, 'Готово');
});

test('climate confirmation is required only for significant changes', () => {
  assert.equal(requiresClimateConfirmation(21, 23), false);
  assert.equal(requiresClimateConfirmation(21, 25), true);
  assert.equal(requiresClimateConfirmation(undefined, 23), true);
});

test('Russian battery question is routed to factual HA tool', () => {
  assert.deepEqual(inferReadTool('У каких устройств низкий заряд?'), [
    'get_low_battery_devices',
    { threshold: 20 },
  ]);
});

test('assistant answers own-name question from local profile without LLM', async () => {
  const provider = {
    chatWithTools: async () => assert.fail('LLM must not be called for profile name'),
  };
  const assistant = new AiOrchestrator({ provider });
  const result = await assistant.chat({
    userId: 'user',
    userName: 'Вася',
    conversationId: 'conversation',
    history: [],
    message: 'Как меня зовут?',
  });
  assert.equal(result.message, 'В вашем профиле указано имя: Вася.');
});

test('assistant answers profile questions in selected English language', async () => {
  const provider = {
    chatWithTools: async () => assert.fail('LLM must not be called for profile name'),
  };
  const assistant = new AiOrchestrator({ provider });
  const result = await assistant.chat({
    userId: 'user',
    userName: 'Vasya',
    conversationId: 'conversation',
    history: [],
    message: 'What is my name?',
    language: 'en',
  });
  assert.equal(result.message, 'Your SmartHouse profile name is Vasya.');
});

test('selected English language is explicitly passed to Qwen', async () => {
  let sentMessages;
  const assistant = new AiOrchestrator({
    provider: {
      chatWithTools: async (messages) => {
        sentMessages = messages;
        return { message: { role: 'assistant', content: 'Hello!' } };
      },
    },
  });
  const result = await assistant.chat({
    userId: 'user',
    conversationId: 'conversation',
    history: [],
    message: 'Tell me about SmartHouse',
    language: 'en',
  });
  assert.equal(result.message, 'Hello!');
  assert.ok(sentMessages.some((item) =>
    item.role === 'system' && /entirely in English/u.test(item.content)));
});

test('assistant never infers the user location from weather history', async () => {
  const provider = {
    chatWithTools: async () => assert.fail('LLM must not guess user location'),
  };
  const assistant = new AiOrchestrator({ provider });
  const result = await assistant.chat({
    userId: 'user',
    conversationId: 'conversation',
    history: [{ role: 'assistant', content: 'Погода в Дербышках: 23.5 °C.' }],
    message: 'Где я сейчас нахожусь?',
  });
  assert.match(result.message, /не могу определить/u);
  assert.match(result.message, /не получает GPS/u);
});

test('assistant identifies outdoor weather provenance without using the LLM', async () => {
  const provider = {
    chatWithTools: async () => assert.fail('LLM must not invent room sensor provenance'),
  };
  const assistant = new AiOrchestrator({ provider });
  const result = await assistant.chat({
    userId: 'user',
    conversationId: 'conversation',
    history: [],
    message: 'Откуда ты взял состояние моей комнаты?',
  });
  assert.match(result.message, /относятся к улице/u);
  assert.match(result.message, /Open-Meteo/u);
  assert.match(result.message, /Home Assistant/u);
});

test('assistant rejects unrelated coding requests without LLM', async () => {
  const provider = {
    chatWithTools: async () => assert.fail('LLM must not handle out-of-scope coding'),
  };
  const assistant = new AiOrchestrator({ provider });
  const result = await assistant.chat({
    userId: 'user',
    conversationId: 'conversation',
    history: [],
    message: 'Напиши HTML и CSS код для сайта-портфолио',
  });
  assert.match(result.message, /только с умным домом/u);
});

test('assistant rejects unrelated historical comparisons without LLM', async () => {
  const provider = {
    chatWithTools: async () => assert.fail('LLM must not answer unrelated history questions'),
  };
  const assistant = new AiOrchestrator({ provider });
  const result = await assistant.chat({
    userId: 'user',
    conversationId: 'conversation',
    history: [],
    message: 'Гитлер или Сталин?',
  });
  assert.match(result.message, /только с умным домом/iu);
  assert.doesNotMatch(result.message, /оба лидера|мировой войны/iu);
});

test('assistant rejects geopolitical comparisons without LLM', async () => {
  const provider = {
    chatWithTools: async () => assert.fail('LLM must not answer geopolitical questions'),
  };
  const assistant = new AiOrchestrator({ provider });
  const result = await assistant.chat({
    userId: 'user',
    conversationId: 'conversation',
    history: [],
    message: 'Евреи или Палестина?',
  });
  assert.match(result.message, /только с умным домом/iu);
  assert.doesNotMatch(result.message, /политически чувствительна|исторических.*аспектов/iu);
});

test('assistant rejects unrelated culinary questions without LLM', async () => {
  const provider = {
    chatWithTools: async () => assert.fail('LLM must not answer culinary questions'),
  };
  const assistant = new AiOrchestrator({ provider });
  const result = await assistant.chat({
    userId: 'user',
    conversationId: 'conversation',
    history: [],
    message: 'Пельмени удмуртские?',
  });
  assert.match(result.message, /только с умным домом/iu);
  assert.doesNotMatch(result.message, /вкусное блюдо|мясной фарш/iu);
});

test('assistant offers relevant smart-home purchasing help without LLM refusal', async () => {
  const provider = {
    chatWithTools: async () => assert.fail('Initial buying clarification must be deterministic'),
  };
  const assistant = new AiOrchestrator({ provider });
  const result = await assistant.chat({
    userId: 'user',
    conversationId: 'conversation',
    history: [],
    message: 'Хочу купить новые датчики, поможешь?',
  });
  assert.match(result.message, /помогу подобрать/iu);
  assert.match(result.message, /протокол/iu);
  assert.match(result.message, /бюджет/iu);
  assert.doesNotMatch(result.message, /не могу помочь с покупками/iu);
});

test('marketplace search only requests allowlisted marketplace URLs', async () => {
  const requested = [];
  const result = await searchMarketplaces('Zigbee датчик протечки', {
    fetchImpl: async (url) => {
      requested.push(new URL(url));
      return {
        ok: true,
        url,
        text: async () => '<html><script type="application/ld+json">' +
          '{"@type":"Product","name":"Test sensor","url":"/product/1",' +
          '"offers":{"price":"1990","priceCurrency":"RUB"}}</script></html>',
      };
    },
  });
  assert.equal(requested.length, 3);
  assert.deepEqual(
    requested.map((url) => url.hostname).sort(),
    ['market.yandex.ru', 'www.ozon.ru', 'www.wildberries.ru'].sort(),
  );
  assert.equal(result.results.length, 3);
  assert.equal(result.results[0].price, '1990');
  assert.match(result.results[0].url, /^https:\/\//u);
});

test('detailed device-shopping request is routed to marketplace search', () => {
  assert.deepEqual(
    inferReadTool('Найди Zigbee датчик протечки до 3000 рублей'),
    [
      'search_marketplaces',
      { query: 'Найди Zigbee датчик протечки до 3000 рублей' },
    ],
  );
});

test('blocked marketplaces produce links instead of invented products', () => {
  const response = exactToolResponse('search_marketplaces', {
    results: [],
    sources: [
      { marketplace: 'Ozon', search_url: 'https://www.ozon.ru/search/?text=zigbee' },
    ],
  }, true);
  assert.match(response, /не буду придумывать/iu);
  assert.match(response, /https:\/\/www\.ozon\.ru/iu);
});

test('assistant does not predict the outcome of an armed conflict', async () => {
  const provider = {
    chatWithTools: async () => assert.fail('LLM must not predict a war outcome'),
  };
  const assistant = new AiOrchestrator({ provider });
  const result = await assistant.chat({
    userId: 'user',
    conversationId: 'conversation',
    history: [{ role: 'assistant', content: 'Температура: 23.5 °C' }],
    message: 'Кто выиграет Россия или Украина?',
  });
  assert.match(result.message, /невозможно достоверно предсказать/iu);
  assert.doesNotMatch(result.message, /температура|влажность/iu);
});

test('assistant never repeats an old unrelated answer as a new response', async () => {
  const stale = 'Температура в комнате 23.5 °C, влажность 84%. Эти показания могут определить комнату.';
  const assistant = new AiOrchestrator({
    provider: {
      chatWithTools: async () => ({ message: { role: 'assistant', content: stale } }),
    },
  });
  const result = await assistant.chat({
    userId: 'user',
    conversationId: 'conversation',
    history: [{ role: 'assistant', content: stale }],
    message: 'Расскажи о своих возможностях',
  });
  assert.match(result.message, /не удалось сформировать ответ именно на новый вопрос/iu);
  assert.notEqual(result.message, stale);
});

test('emoji-only follow-up inherits Russian and removes CJK text', async () => {
  let calls = 0;
  const assistant = new AiOrchestrator({
    provider: {
      chatWithTools: async () => {
        calls += 1;
        return calls === 1
          ? { message: { role: 'assistant', content: 'Отлично настроены! 如果需要更多帮助。' } }
          : { message: { role: 'assistant', content: 'Отлично! Чем ещё помочь?' } };
      },
    },
  });
  const result = await assistant.chat({
    userId: 'user',
    conversationId: 'conversation',
    history: [{ role: 'user', content: 'Спасибо за помощь' }],
    message: '🙂🙂🙂',
  });
  assert.equal(calls, 2);
  assert.equal(result.message, 'Отлично! Чем ещё помочь?');
  assert.doesNotMatch(result.message, /[\u4E00-\u9FFF]/u);
});

test('energy question is routed to factual HA tool', () => {
  assert.deepEqual(inferReadTool('Сколько энергии потрачено сегодня?'), [
    'get_energy_usage',
    {},
  ]);
});

test('Home Assistant event history remains in scope', () => {
  assert.equal(
    inferReadTool('Что происходило дома за последние 12 часов?')?.[0],
    'get_home_summary',
  );
});

test('cold room question requests current room temperature first', () => {
  assert.deepEqual(inferReadTool('Почему в спальне холодно?'), [
    'get_temperature',
    { room: 'спальне' },
  ]);
});

test('weather question is routed to the public weather tool', () => {
  assert.deepEqual(inferReadTool('Какая погода в Казани?'), [
    'get_weather',
    { location: 'казани' },
  ]);
});

test('public weather uses only allowlisted Open-Meteo endpoints', async () => {
  const requested = [];
  const result = await getPublicWeather('Казани', {
    fetchImpl: async (url) => {
      requested.push(String(url));
      if (String(url).startsWith('https://geocoding-api.open-meteo.com/')) {
        return {
          ok: true,
          json: async () => ({
            results: [{ name: 'Казань', admin1: 'Татарстан', country: 'Россия', latitude: 55.79, longitude: 49.12 }],
          }),
        };
      }
      return {
        ok: true,
        json: async () => ({
          current: {
            time: '2026-08-14T12:00',
            temperature_2m: 21,
            apparent_temperature: 20,
            relative_humidity_2m: 60,
            precipitation: 0,
            weather_code: 1,
            wind_speed_10m: 8,
          },
        }),
      };
    },
  });
  assert.equal(result.location.name, 'Казань');
  assert.equal(result.source, 'Open-Meteo');
  assert.equal(requested.length, 2);
  assert.ok(requested.every((url) => new URL(url).hostname.endsWith('open-meteo.com')));
});

test('public weather strips a residential-complex prefix before geocoding', async () => {
  const geocodingUrls = [];
  await getPublicWeather('ЖК Дербышках', {
    fetchImpl: async (url) => {
      if (String(url).startsWith('https://geocoding-api.open-meteo.com/')) {
        geocodingUrls.push(String(url));
        const query = new URL(url).searchParams.get('name');
        return {
          ok: true,
          json: async () => query === 'Дербышки'
            ? { results: [{ name: 'Дербышки', latitude: 55.86, longitude: 49.27 }] }
            : {},
        };
      }
      return {
        ok: true,
        json: async () => ({
          current: {
            time: '2026-08-14T12:00',
            temperature_2m: 23,
            apparent_temperature: 24,
            relative_humidity_2m: 70,
            precipitation: 0,
            weather_code: 2,
            wind_speed_10m: 5,
          },
        }),
      };
    },
  });
  assert.deepEqual(geocodingUrls.map((url) => new URL(url).searchParams.get('name')), [
    'Дербышках',
    'Дербышки',
  ]);
});

test('weather response is deterministic and does not ask the LLM to reinterpret facts', async () => {
  const result = exactToolResponse('get_weather', {
    status: 'ok',
    location: { name: 'Владивосток', region: 'Приморский край' },
    weather: 'морось',
    temperature_c: 24.9,
    feels_like_c: 28.4,
    humidity_percent: 80,
    precipitation_mm: 0.2,
    wind_kmh: 6.4,
    source: 'Open-Meteo',
  }, true);
  assert.match(result, /морось/u);
  assert.match(result, /24\.9 °C/u);
  assert.doesNotMatch(result, /мороз|получение данных/iu);
});

test('two-time lighting request is routed to a scheduled automation draft', () => {
  const inferred = inferAutomationTool(
    'Добавь автоматизацию: в гостиной лампа включается в 5:00 утра и выключается в 5:00 вечера',
  );
  assert.deepEqual(inferred, ['prepare_scheduled_automation_draft', {
    name: 'Расписание освещения',
    room: 'гостиной',
    device: 'лампа',
    turn_on_at: '05:00',
    turn_off_at: '17:00',
  }]);
});

test('voice-style schedule request works without the word automation', () => {
  const inferred = inferAutomationTool(
    'Когда время 5:00 утра лампа включается, когда время 5:00 вечера она выключается, лампа в гостиной',
  );
  assert.equal(inferred?.[0], 'prepare_scheduled_automation_draft');
  assert.equal(inferred?.[1].turn_off_at, '17:00');
});
