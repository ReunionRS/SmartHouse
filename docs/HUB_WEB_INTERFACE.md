# SmartHouse hub web interface

The customer-facing hub interface is the Flutter web application exposed by
the `smarthouse-web` service on port `8080`. Home Assistant remains the local
automation engine and its port `8123` is reserved for setup, recovery and
service administration.

## Local development

```sh
docker compose up -d --build
```

Open `http://localhost:8080` for SmartHouse. The application sends `/api`,
`/uploads` and OAuth helper requests to the backend through the same origin,
so the same image also works when the hub is opened by its LAN address.

The Home Assistant interface at `http://localhost:8123` is not the product UI.
For a release appliance, restrict that port to the service network or expose it
only through an authenticated maintenance mode.

## Release checklist

- Serve the web panel and API behind HTTPS or a trusted local TLS endpoint.
- Do not publish port 8123 to the customer LAN by default.
- Keep a documented recovery procedure for service technicians.
- Preserve all upstream licenses and attribution notices in the shipped image.
- Do not use Home Assistant names or logos as SmartHouse product branding.
- Test OAuth callback and WebSocket connectivity using the hub LAN hostname.

## Local data boundary

PostgreSQL is the source of truth for accounts, profiles, application state,
AI conversations and audit records. Uploaded avatars use a persistent Docker
volume. Home Assistant keeps device state and history in its local `/config`
volume. The client stores only session/cache and presentation preferences.

Cloud push registration is disabled. Hub notifications must be transported by
the local authenticated connection and displayed as an on-device notification.
