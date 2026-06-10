# Aceso

A self-hosted platform for tracking health and recovery data from wearables like Whoop. You own the server, you own the data.

---

## What it is

Aceso pulls in your health metrics (recovery, strain, sleep) and gives you a private dashboard to explore them. No third-party cloud required. Run it on a home server, a VPS, or a Raspberry Pi.

The platform has three parts:

- **iOS app** - native SwiftUI client for on-device access
- **Web dashboard** - TanStack Start (React, SSR) for browser access
- **Go server** - source of truth for all data; handles ingest, the HTTP API, and live updates over WebSockets

An optional addon system lets you extend any of the three platforms without modifying core code.

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

### Docker

```bash
git clone https://github.com/your-username/aceso.git
cd aceso
docker compose -f docker/docker-compose.yml up --build
```

The server starts on port `8080` and the web dashboard on port `3000`.

### From source

**Server**
```bash
make dev-server
```

**Web**
```bash
cd apps/web && npm install
make dev-web
```

**iOS** - open `apps/ios/Aceso.xcodeproj` in Xcode and run on a simulator or device.

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

## Project layout

```
Aceso/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug-report.yml
│   │   └── feature-request.yml
│   ├── workflows/
│   │   ├── ci.yml
│   │   └── release.yml
│   └── PULL_REQUEST_TEMPLATE.md
├── addons/
│   ├── _template/              starter template for new addons
│   │   ├── addon.json
│   │   ├── ios/
│   │   ├── server/
│   │   └── web/
│   ├── apple-health/           writes metrics to HealthKit
│   ├── export-csv/             CSV export from the web dashboard
│   ├── notifications/          server-side webhook notifications
│   └── widgets/                iOS home screen widgets
├── apps/
│   ├── ios/
│   │   ├── Aceso/
│   │   │   ├── screens/        feature screens (recovery, sleep, strain)
│   │   │   ├── shared/         reusable components, extensions, models
│   │   │   ├── aceso-app.swift
│   │   │   ├── addon-loader.swift
│   │   │   └── content-view.swift
│   │   ├── AcesoTests/         Swift Testing unit tests
│   │   ├── AcesoUITests/       XCUITest UI tests
│   │   └── Aceso.xcodeproj/
│   └── web/
│       ├── e2e/                Playwright tests
│       ├── src/
│       │   ├── components/
│       │   │   ├── layout/     header, footer
│       │   │   └── ui/         theme-toggle and other primitives
│       │   ├── lib/            api.ts, ws.ts
│       │   ├── routes/         TanStack Router file routes
│       │   ├── addon-loader.ts
│       │   └── router.tsx
│       ├── playwright.config.ts
│       ├── package.json
│       └── vite.config.ts
├── docker/
│   ├── Dockerfile
│   └── docker-compose.yml
├── docs/
│   ├── addons.md
│   ├── architecture.md
│   ├── conventions.md
│   └── self-hosting.md
├── server/
│   ├── cmd/server/
│   │   └── main.go
│   ├── e2e/                    Go e2e tests (build tag: e2e)
│   ├── internal/
│   │   ├── api/
│   │   ├── db/
│   │   ├── ingest/
│   │   ├── live/
│   │   └── middleware/
│   ├── addon-loader.go
│   └── go.mod
├── AGENTS.md
├── LICENSE
├── Makefile
└── README.md
```

---

## Conventions

All files and folders use `kebab-case`. Identifiers inside files follow each language's own rules (Go `camelCase`, Swift/TS `PascalCase` for types, etc.). Only the filename itself is governed by the rule.

Forced exceptions where a tool requires a specific name: `Makefile`, `Dockerfile`, `Package.swift`, `go.mod`, `main.go`, `*_test.go`, `package.json`, `__root.tsx`, `routeTree.gen.ts`, and the Xcode project folders (`Aceso/`, `AcesoTests/`, `AcesoUITests/`, `Aceso.xcodeproj/`).

Import order:
- **Go** - stdlib, then third-party, then internal (blank line between each group)
- **Swift** - system frameworks, then internal modules
- **TypeScript** - external packages, then `#/` internal aliases, then relative paths

Comments explain why, not what. If removing the comment would not confuse a future reader, don't write it.

Full details are in `docs/conventions.md`. `AGENTS.md` at the repo root is the single source of truth for anyone (human or AI) working in this repository.

---

## Addons

Addons live in `addons/<name>/` and are separate from the core apps. Each addon can ship code for any combination of iOS, web, and server. They register themselves at startup; the core apps never import addon code directly.

To create one, copy `addons/_template/` and fill in `addon.json`. See `docs/addons.md` for the full guide.

---

## Contributing

Read `AGENTS.md` before opening a PR. It covers naming rules, import order, testing requirements, and CI security rules that all contributions must follow.

For bugs and feature requests, use the issue templates.

---

## License

MIT - see `LICENSE`.
