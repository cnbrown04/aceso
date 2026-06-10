# Aceso

A self-hosted platform for tracking health and recovery data from wearables like Whoop. You own the server, you own the data.

---

## What it is

Aceso pulls in your health metrics — recovery, strain, sleep — and gives you a private dashboard to explore them. No third-party cloud required. Run it on a home server, a VPS, or a Raspberry Pi.

The platform is three things working together:

- **iOS app** — native SwiftUI client for viewing and interacting with your data on device
- **Web dashboard** — TanStack Start (React, SSR) for browser-based access
- **Go server** — the source of truth; handles data ingest, the HTTP API, and live updates over WebSockets

An optional **addon system** lets you extend any of the three platforms without modifying core code.

---

## Tech stack

| Layer | Technology |
|---|---|
| iOS | SwiftUI, Swift Testing, XCUITest |
| Web | TanStack Start, TanStack Router, Vite, Playwright |
| Server | Go 1.23, `net/http` |
| Infrastructure | Docker, docker-compose |

---

## Getting started

### Docker (quickest)

```bash
git clone https://github.com/your-username/aceso.git
cd aceso
docker compose -f docker/docker-compose.yml up --build
```

The server starts on port `8080` and the web dashboard on port `3000`.

### From source

**Server**
```bash
make dev-server   # runs go run ./cmd/server
```

**Web**
```bash
cd apps/web && npm install
make dev-web      # runs npm run dev
```

**iOS** — open `apps/ios/Aceso.xcodeproj` in Xcode and run on a simulator or device.

---

## Running tests

```bash
make test-server        # Go unit tests
make test-server-e2e    # Go e2e tests (httptest)
make test-web           # Vitest unit tests
make test-e2e           # Playwright browser tests
```

iOS tests run through Xcode (`Cmd+U`) or CI.

---

## Addons

Addons live in `addons/<name>/` and are entirely separate from the core apps. Each addon can ship code for any combination of iOS, web, and server. They register themselves at startup — the core apps never import addon code directly.

To create one, copy `addons/_template/` and fill in `addon.json`.

See `docs/addons.md` for the full guide.

---

## Project layout

```
Aceso/
├── addons/        optional feature packages
├── apps/
│   ├── ios/       SwiftUI app
│   └── web/       TanStack Start dashboard
├── server/        Go HTTP server
├── docker/        Dockerfile + docker-compose.yml
├── docs/          architecture, conventions, addon guide, self-hosting
└── Makefile
```

---

## Contributing

Read `AGENTS.md` before opening a PR — it covers naming conventions, import order, testing requirements, and CI security rules that all contributions must follow.

For bugs and feature requests, use the issue templates.

---

## License

MIT
