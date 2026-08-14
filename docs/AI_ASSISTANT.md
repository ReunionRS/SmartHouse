# SmartHouse AI Assistant

Локальный AI-ассистент использует Qwen через Ollama. Flutter не обращается к модели или Home Assistant напрямую: запрос проходит через авторизованный SmartHouse Backend, а модель получает только нормализованные результаты разрешённых инструментов.

## Архитектура

`Flutter -> POST /api/ai/chat -> AI Orchestrator -> Ollama/Qwen + HA Tool Layer -> Home Assistant`

HA access/refresh tokens расшифровываются только внутри существующего HA service и никогда не включаются в prompt или tool result. Атрибуты entities фильтруются по whitelist.

## Локальный запуск

```powershell
ollama pull qwen2.5:7b
docker compose up -d --build
```

Backend в Docker использует `http://host.docker.internal:11434`. При запуске backend напрямую задайте `QWEN_BASE_URL=http://localhost:11434`.

Основные переменные описаны в `backend/.env.example`:

- `AI_ENABLED`
- `AI_PROVIDER`
- `QWEN_BASE_URL`
- `QWEN_MODEL`
- `AI_MAX_TOOL_ROUNDS`
- `AI_TIMEOUT_MS`
- `AI_CONFIRMATION_TTL_SECONDS`

На RTX 3050 холодная загрузка `qwen2.5:7b` может занять больше минуты, поэтому локальный timeout установлен в 120 секунд.

## API

```bash
curl -X POST http://localhost:4000/api/ai/chat \
  -H "Authorization: Bearer <SMART_HOUSE_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"message":"Что сейчас происходит дома?"}'
```

Ответ содержит `conversationId`, `message`, `type`, `data`, `actions` и `suggestions`. История диалога хранится локально в PostgreSQL и привязана к пользователю.

## Реализованные инструменты MVP

- `get_home_summary`, `get_rooms`, `get_room_state`, `get_device_state`
- `get_lights_state`, `get_openings_state`
- `get_low_battery_devices`, `get_unavailable_devices`
- `turn_on_device`, `turn_off_device`, `set_light_brightness`, `run_scene`
- `prepare_automation_draft` (только черновик, без сохранения в HA)

Команды ограничены явным списком доменов и действий. Произвольный вызов `/api/services` модели недоступен. Каждый tool call записывается в локальный `ai_audit_log`.

## Текущие ограничения

- Streaming, история HA, energy tools, подтверждения high-risk операций и полноценное сохранение automation относятся к следующим этапам.
- В MVP модели вообще не предоставлены lock/alarm/garage write-tools.
- Реальное состояние зависит от доступности подключённого Home Assistant.

## Проверка

```powershell
cd backend
npm test

cd ../frontend
fvm flutter analyze
```
