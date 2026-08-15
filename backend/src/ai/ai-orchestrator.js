import fs from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { config } from '../config.js';
import { saveAudit } from './conversation-store.js';
import { aiToolDefinitions, executeAiTool } from './tools/ai-tools.js';
import { createConfirmation } from './safety/confirmation-service.js';

let systemPrompt;
const getSystemPrompt = async () => {
  systemPrompt ||= fs.readFile(fileURLToPath(new URL('./prompts/smart-house-assistant.txt', import.meta.url)), 'utf8');
  return systemPrompt;
};

const parseArguments = (raw) => {
  if (raw && typeof raw === 'object') return raw;
  try { return JSON.parse(raw || '{}'); } catch { return {}; }
};

export const inferReadTool = (message) => {
  const text = message.toLocaleLowerCase('ru-RU');
  if (/(?:найди|покажи|подбери|посоветуй|купить)[^?]*(?:датчик|ламп|выключател|розетк|реле|шлюз|хаб|устройств)|(?:датчик|ламп|выключател|розетк|реле|шлюз|хаб|устройств)[^?]*(?:маркетплейс|магазин|цена|купить)/iu.test(text)) {
    return ['search_marketplaces', { query: String(message).trim() }];
  }
  const weatherLocation = text.match(/(?:погода|температура на улице|прогноз)[^?]*?(?:в|во|для)\s+([а-яёa-z-]+(?:\s+[а-яёa-z-]+)?)/iu);
  if (weatherLocation) {
    return ['get_weather', { location: weatherLocation[1].trim() }];
  }
  const roomTemperature = text.match(/(?:температур|холодн|жарк|тепл)[^?]*?(?:в|на)\s+([а-яё-]+)/u)
    || text.match(/(?:в|на)\s+([а-яё-]+)[^?]*?(?:температур|холодн|жарк|тепл)/u);
  if (roomTemperature) return ['get_temperature', { room: roomTemperature[1] }];
  if (/что.*(происходит|дома)|сводк|состояние дома|хаб/.test(text)) return ['get_home_summary', {}];
  if (/низк.*заряд|батаре/.test(text)) return ['get_low_battery_devices', { threshold: 20 }];
  if (/открыт.*(окн|двер)|окн.*открыт|про.м/.test(text)) return ['get_openings_state', {}];
  if (/(где|какие|сколько).*(свет|ламп)|свет.*(включ|горит)/.test(text)) return ['get_lights_state', {}];
  if (/недоступн.*устройств|устройств.*не отвеч/.test(text)) return ['get_unavailable_devices', {}];
  if (/энерг|электр|потреблен|мощност/.test(text)) return ['get_energy_usage', {}];
  if (/(?:какие|сколько)[^?]*комнат|список комнат/.test(text)) return ['get_rooms', {}];
  if (/(?:какие|что|покажи|список)[^?]*устройств[^?]*(?:подключ|добав|прилож|главн)|устройств[^?]*(?:подключ|добав)[^?]*(?:прилож|главн)/u.test(text)) {
    return ['get_devices', { favorites_only: /избран|главн.*экран/u.test(text) }];
  }
  return null;
};

export const inferAutomationTool = (message) => {
  const text = String(message || '').toLocaleLowerCase('ru-RU');
  const matches = [...text.matchAll(/(\d{1,2})[:.](\d{2})(?:\s*(утра|дня|вечера|ночи))?/gu)];
  const asksAutomation = /(?:добав|созд|сдел).*автоматизац|автоматизац.*(?:добав|созд|сдел)/u.test(text);
  const wantsOn = /включ/u.test(text);
  const wantsOff = /(?:выключ|отключ)/u.test(text);
  if ((!asksAutomation && matches.length < 2) || (!wantsOn && !wantsOff) || matches.length < 1) return null;
  const normalize = (match) => {
    let hour = Number(match[1]);
    const period = match[3] || '';
    if ((period === 'вечера' || period === 'дня') && hour < 12) hour += 12;
    if (period === 'ночи' && hour === 12) hour = 0;
    return `${String(hour).padStart(2, '0')}:${match[2]}`;
  };
  const room = text.match(/(?:в|на)\s+([а-яё-]+)\s+(?:(?:у\s+меня\s+)?есть\s+)?(?:ламп|свет)/u)?.[1]
    || text.match(/(?:ламп|свет)[^.!?]{0,30}(?:в|на)\s+([а-яё-]+)/u)?.[1];
  if (!room) return null;
  return ['prepare_scheduled_automation_draft', {
    name: 'Расписание освещения', room, device: 'лампа',
    ...(wantsOn ? { turn_on_at: normalize(matches[0]) } : {}),
    ...(wantsOff ? { turn_off_at: normalize(matches[wantsOn && matches.length > 1 ? 1 : 0]) } : {}),
  }];
};

const containsCjk = (value) => /[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]/u.test(value);
const isRussianRequest = (value) => /[А-Яа-яЁё]/u.test(value);
const conversationPrefersRussian = (message, history) => {
  if (isRussianRequest(message)) return true;
  for (const item of [...history].reverse()) {
    const content = String(item.content || '');
    if (isRussianRequest(content)) return true;
    if (/[A-Za-z]/u.test(content)) return false;
  }
  return false;
};
const containsFakeProgress = (value) => /(?:^|\n)\s*(?:получаю|проверяю|запрашиваю|анализирую|связываюсь|ищу)\b/imu.test(value);
const normalizedAnswer = (value) => String(value || '')
  .toLocaleLowerCase('ru-RU')
  .replace(/\s+/gu, ' ')
  .trim();
const repeatsPreviousAssistantAnswer = (content, history) => {
  const answer = normalizedAnswer(content);
  if (answer.length < 50) return false;
  return history.some((item) =>
    item.role === 'assistant' && normalizedAnswer(item.content) === answer);
};
const isClearlyOutOfScope = (value) => {
  const text = String(value || '').toLocaleLowerCase('ru-RU');
  if (/(?:сколько\s+будет|реши(?:ть)?\s+(?:пример|уравнен)|вычисли|математик)|(?:calculate|solve|what\s+is)\s*-?\d[^?]*(?:[+*/×÷-])/iu.test(text)) {
    return true;
  }
  return /(html|css|javascript|typescript|python|java|c\+\+|php|sql|код|программ|сайт|портфолио|реферат|сочинени|домашн.*задани|курсов|резюме|стих|рецепт|кулинар|блюд|пельмен|готов(?:ить|ка)|еда|продукт(?:ы|ов)|гитлер|сталин|ленин|вторая\s+мировая|первая\s+мировая|историческ.*событ|политик|геополитик|президент|император|диктатор|израил|палестин|сектор\s+газа|хамас|нато|военн|войн|вооруж[её]нн.*конфликт)/u.test(text)
    && !/(home assistant|smart ?house|умн.*дом|автоматизац|интеграц|датчик|устройств)/u.test(text);
};

export const exactToolResponse = (name, result, russian) => {
  if (name === 'search_marketplaces' && !result?.results?.length) {
    const links = (result?.sources || [])
      .filter((source) => source?.marketplace && source?.search_url)
      .map((source) => `- [${source.marketplace}](${source.search_url})`)
      .join('\n');
    return russian
      ? `Маркетплейсы не разрешили автоматически получить карточки и актуальные цены. Я не буду придумывать предложения. Откройте готовые поиски:\n\n${links}`
      : `The marketplaces blocked automated product-card access. Open these prepared searches instead:\n\n${links}`;
  }
  if (name === 'get_weather') {
    if (result?.error === 'LOCATION_NOT_FOUND') {
      return russian
        ? `Не удалось найти населённый пункт «${result.requested_location || ''}». Уточните город, район или название места.`
        : `The location “${result.requested_location || ''}” was not found. Please clarify it.`;
    }
    if (result?.error) {
      return russian
        ? 'Не удалось получить актуальную погоду из метеосервиса. Попробуйте немного позже.'
        : 'Current weather data is temporarily unavailable.';
    }
    const place = [result.location?.name, result.location?.region]
      .filter(Boolean)
      .join(', ');
    if (russian) {
      const precipitation = Number(result.precipitation_mm || 0) > 0
        ? ` Осадки: ${result.precipitation_mm} мм.`
        : ' Осадков сейчас нет.';
      return `Сейчас в ${place}: ${result.weather}, ${result.temperature_c} °C, ощущается как ${result.feels_like_c} °C. Влажность ${result.humidity_percent}%, ветер ${result.wind_kmh} км/ч.${precipitation} Источник: ${result.source}.`;
    }
    return `Current weather in ${place}: ${result.weather}, ${result.temperature_c} °C, feels like ${result.feels_like_c} °C. Humidity ${result.humidity_percent}%, wind ${result.wind_kmh} km/h. Source: ${result.source}.`;
  }
  if (result?.error === 'ROOM_NOT_FOUND') {
    return russian
      ? 'Такая комната не найдена в Home Assistant. Сначала добавьте комнату и привяжите к ней датчик.'
      : 'That room was not found in Home Assistant.';
  }
  if ((name === 'get_temperature' || name === 'get_humidity') && result.status === 'no_data') {
    return russian
      ? `В комнате «${result.room?.name || ''}» нет датчика ${name === 'get_temperature' ? 'температуры' : 'влажности'}, поэтому актуальных данных нет.`
      : 'No matching sensor data is available for that room.';
  }
  if (name === 'get_energy_usage' && result.status === 'no_data') {
    return russian
      ? 'Home Assistant пока не получает данные об энергопотреблении. Подключите совместимый счётчик энергии или устройство с датчиком мощности.'
      : 'Home Assistant is not receiving energy-usage data yet. Connect a compatible energy meter or power sensor.';
  }
  if (name === 'get_home_summary' && result.home_status === 'no_devices') {
    return russian
      ? 'Хаб Home Assistant работает, но устройства умного дома пока не подключены.'
      : 'The Home Assistant hub is online, but no smart-home devices are connected yet.';
  }
  if (name === 'get_rooms' && Array.isArray(result.rooms)) {
    if (!result.rooms.length) {
      return russian ? 'В SmartHouse пока нет созданных комнат.' : 'There are no rooms in SmartHouse yet.';
    }
    const names = result.rooms.map((room) => room.name || room.id).filter(Boolean);
    return russian
      ? `Сейчас создано комнат: ${names.length}.\n\n${names.map((item, index) => `${index + 1}. ${item}`).join('\n')}`
      : `Rooms currently created: ${names.length}.\n\n${names.map((item, index) => `${index + 1}. ${item}`).join('\n')}`;
  }
  if (name === 'get_devices' && Array.isArray(result.devices)) {
    if (!result.devices.length) {
      return russian ? 'Подходящих устройств сейчас не найдено.' : 'No matching devices were found.';
    }
    const lines = result.devices.map((device, index) => {
      const room = device.room_name || device.room_id || (russian ? 'без комнаты' : 'no room');
      const state = device.state === 'on'
        ? (russian ? 'включено' : 'on')
        : device.state === 'off'
          ? (russian ? 'выключено' : 'off')
          : String(device.state || '');
      return `${index + 1}. ${device.name} — ${room}${state ? `, ${state}` : ''}`;
    });
    return russian
      ? `Найдено устройств: ${result.devices.length}.\n\n${lines.join('\n')}`
      : `Devices found: ${result.devices.length}.\n\n${lines.join('\n')}`;
  }
  if (name !== 'get_low_battery_devices') return null;
  if (result.status === 'no_devices') {
    return russian
      ? 'Сейчас к Home Assistant не подключено ни одного устройства, поэтому данных о заряде нет.'
      : 'No devices are connected to Home Assistant, so battery data is unavailable.';
  }
  if (result.status === 'no_battery_data') {
    return russian
      ? 'Home Assistant не обнаружил ни одного устройства, передающего данные о заряде батареи.'
      : 'Home Assistant found no devices reporting battery data.';
  }
  return null;
};

export class AiOrchestrator {
  constructor({ provider, toolExecutor = executeAiTool, maxToolRounds = config.ai.maxToolRounds }) {
    this.provider = provider;
    this.toolExecutor = toolExecutor;
    this.maxToolRounds = maxToolRounds;
  }

  async chat({ userId, userName = '', homeId = '', conversationId, history, message, language = '' }) {
    const russian = language === 'en'
      ? false
      : language === 'ru'
        ? true
        : conversationPrefersRussian(message, history);
    const asksSmartHomeBuyingHelp =
      /(?:купить|покупк|подобр|посовет|рекоменд)[^?]*(?:датчик|ламп|выключател|розетк|реле|шлюз|хаб|устройств)|(?:датчик|ламп|выключател|розетк|реле|шлюз|хаб|устройств)[^?]*(?:купить|покупк|подобр|посовет|рекоменд)/iu.test(
        message,
      );
    if (asksSmartHomeBuyingHelp &&
        !/(?:бюджет|до\s+\d|zigbee|z-wave|matter|wi-?fi|модель|протокол|регион|город)/iu
            .test(message)) {
      return {
        message: russian
            ? 'Да, помогу подобрать совместимые устройства для SmartHouse и Home Assistant. Уточните, пожалуйста: какие датчики нужны, какой протокол вы используете (Zigbee, Z-Wave, Matter или Wi‑Fi), какой бюджет и в каком регионе планируете покупать?'
            : 'Yes. I can help choose devices compatible with SmartHouse and Home Assistant. Tell me the device type, protocol, budget, and purchase region.',
        type: 'text',
        data: null,
      };
    }
    const asksConflictPrediction = /(?:кто\s+(?:выиграет|победит)|чья\s+победа|чем\s+закончится)[^?]*(?:росси|украин|войн|конфликт)|(?:росси|украин)[^?]*(?:выиграет|победит)/iu.test(message);
    if (asksConflictPrediction) {
      return {
        message: 'Невозможно достоверно предсказать исход войны или назвать будущего победителя. SmartHouse Assistant не должен выдавать предположения о вооружённом конфликте за факт. Я могу помочь с вашим умным домом и функциями SmartHouse.',
        type: 'text',
        data: null,
      };
    }
    if (isClearlyOutOfScope(message)) {
      return {
        message: russian
          ? 'Я помогаю только с умным домом, Home Assistant и функциями SmartHouse. Могу проверить устройства, состояние дома, историю событий или помочь создать автоматизацию.'
          : 'I can only help with your smart home, Home Assistant, and SmartHouse features.',
        type: 'text',
        data: null,
      };
    }
    const asksOwnName = /(как меня зовут|мо[её] имя|знаешь.*мо[её] имя|what(?:'s| is) my name|do you know my name)/iu.test(message);
    if (asksOwnName) {
      return {
        message: russian
          ? userName
            ? `В вашем профиле указано имя: ${userName}.`
            : 'В вашем профиле SmartHouse имя пока не указано.'
          : userName
            ? `Your SmartHouse profile name is ${userName}.`
            : 'Your SmartHouse profile does not have a name yet.',
        type: 'text',
        data: null,
      };
    }
    const asksCurrentLocation = /(?:где я|где мы)\s+(?:сейчас\s+)?нахожусь|определи(?:ть)?\s+мо[её]\s+местоположен|какая у меня геолокац/iu.test(message);
    if (asksCurrentLocation) {
      return {
        message: 'Я не могу определить, где вы сейчас находитесь: SmartHouse Assistant не получает GPS-координаты телефона. Погода по указанному городу также не подтверждает ваше местоположение.',
        type: 'text',
        data: null,
      };
    }
    const asksRoomDataProvenance = /откуда.*(?:состояни|данн|температур|влажност).*комнат|где.*(?:взял|получил).*данн.*комнат/iu.test(message);
    if (asksRoomDataProvenance) {
      return {
        message: 'Эти значения нельзя считать состоянием комнаты. Температура и влажность из ответа о погоде относятся к улице и получены через Open-Meteo. Данные комнаты можно назвать только после запроса датчиков температуры и влажности из Home Assistant.',
        type: 'text',
        data: null,
      };
    }
    const messages = [
      { role: 'system', content: await getSystemPrompt() },
      {
        role: 'system',
        content: russian
          ? 'Обязательный язык ответа в этом диалоге — русский. Отвечай полностью на русском языке.'
          : 'The required response language for this conversation is English. Answer entirely in English.',
      },
      {
        role: 'system',
        content: userName
          ? `Локальный профиль текущего пользователя: имя «${userName}». Используй это имя только когда пользователь спрашивает о себе или когда уместно персональное обращение. Не выдумывай другие данные профиля.`
          : 'В локальном профиле пользователя имя не указано. Не выдумывай имя.',
      },
      ...history.map((item) => ({ role: item.role, content: item.content })),
    ];
    let responseType = 'text';
    let responseData = null;
    const inferred = inferAutomationTool(message) || inferReadTool(message);
    if (inferred) {
      const [name, args] = inferred;
      const started = Date.now();
      const toolResult = await this.toolExecutor({ userId, name, args });
      await saveAudit({
        userId, homeId, conversationId, tool: name, result: toolResult?.error ? String(toolResult.error) : 'success',
        latencyMs: Date.now() - started,
      });
      messages.push({
        role: 'system',
        content: `Backend заранее получил актуальные данные через ${name}. Ответь на запрос, используя только эти данные: ${JSON.stringify(toolResult)}`,
      });
      if (name === 'get_home_summary') {
        responseType = 'home_summary';
        responseData = toolResult;
      }
      if (toolResult?.type === 'automation_draft') {
        return {
          message: russian
            ? 'Я нашёл устройство в Home Assistant и подготовил расписание. Проверьте его и нажмите «Создать в Home Assistant».'
            : 'I found the device in Home Assistant and prepared the schedule. Review and confirm it.',
          type: 'automation_draft',
          data: toolResult.draft,
        };
      }
      const exactResponse = exactToolResponse(
        name,
        toolResult,
        russian,
      );
      if (exactResponse) {
        return { message: exactResponse, type: 'text', data: null };
      }
    }
    messages.push({ role: 'user', content: message });
    for (let round = 0; round < this.maxToolRounds; round += 1) {
      const result = await this.provider.chatWithTools(messages, aiToolDefinitions);
      const assistant = result.message;
      const calls = Array.isArray(assistant.tool_calls) ? assistant.tool_calls : [];
      if (!calls.length) {
        let content = String(assistant.content || '').trim();
        if (repeatsPreviousAssistantAnswer(content, history)) {
          content = russian
            ? 'Не удалось сформировать ответ именно на новый вопрос. Попробуйте переформулировать его.'
            : 'I could not produce an answer to the new question. Please rephrase it.';
        }
        if (containsCjk(content) || (russian && containsFakeProgress(content))) {
          messages.push(assistant);
          messages.push({
            role: 'user',
            content: russian
              ? 'Перепиши предыдущий ответ полностью на русском языке. Не используй китайские иероглифы. Не пиши статусы процесса вроде «проверяю», «получаю» или «анализирую»: пользователь увидит только окончательный результат. Не добавляй новых фактов.'
              : 'Rewrite the previous answer completely in English. Do not use Chinese, Japanese, or Korean characters. Return only the final answer and do not add new facts.',
          });
          const corrected = await this.provider.chatWithTools(messages, []);
          content = String(corrected.message?.content || '').trim();
          if (containsCjk(content) || containsFakeProgress(content)) {
            content = russian
              ? 'Не удалось корректно сформировать ответ на русском языке. Попробуйте повторить запрос.'
              : 'I could not produce an answer in the requested language. Please try again.';
          }
        }
        return { message: content || 'Не удалось сформировать ответ.', type: responseType, data: responseData };
      }
      messages.push(assistant);
      for (const call of calls) {
        const name = String(call.function?.name || '');
        const args = parseArguments(call.function?.arguments);
        const started = Date.now();
        let toolResult;
        try {
          toolResult = await this.toolExecutor({ userId, name, args });
        } catch (error) {
          toolResult = { error: error.code || 'TOOL_ERROR', message: error.message };
        }
        if (toolResult?.requires_confirmation) {
          const confirmation = await createConfirmation({
            userId,
            conversationId,
            tool: toolResult.action.tool,
            args: toolResult.action.args,
          });
          toolResult = { requires_confirmation: true, confirmation };
          responseType = 'confirmation';
          responseData = confirmation;
        }
        if (toolResult?.type === 'automation_draft') {
          responseType = 'automation_draft';
          responseData = toolResult.draft;
        }
        await saveAudit({
          userId, homeId, conversationId, tool: name,
          target: String(args.device || args.scene || args.room || ''),
          result: toolResult?.error ? String(toolResult.error) : 'success',
          latencyMs: Date.now() - started,
        });
        const exactResponse = exactToolResponse(name, toolResult, russian);
        if (exactResponse) {
          return { message: exactResponse, type: 'text', data: null };
        }
        messages.push({ role: 'tool', content: JSON.stringify(toolResult) });
      }
    }
    const error = new Error('Модель превысила лимит обращений к данным дома');
    error.code = 'LLM_MAX_TOOL_ROUNDS';
    error.statusCode = 502;
    throw error;
  }
}
