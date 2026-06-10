# Architecture

```
┌─────────────────────────────────────────────────────┐
│                    apps/ios                         │
│  AddonLoader ← addons/*/ios (Swift packages)        │
└───────────────────────┬─────────────────────────────┘
                        │ HTTP / WebSocket
┌───────────────────────▼─────────────────────────────┐
│                    server/                          │
│  addon-loader.go ← addons/*/server (Go packages)    │
│  internal/{ingest, api, live, db, middleware}        │
└───────────────────────┬─────────────────────────────┘
                        │ HTTP
┌───────────────────────▼─────────────────────────────┐
│                    apps/web                         │
│  addon-loader.ts ← addons/*/web (TS modules)        │
└─────────────────────────────────────────────────────┘
```

## Key decisions

- **Addon isolation**: addons live entirely under `addons/` and are never imported by each other.
- **Go backend**: single binary, ships in Docker. SQLite for local self-hosting; Postgres for multi-user deployments.
- **Web**: React + Vite. Addons are tree-shaken at build time via `import.meta.glob`.
- **iOS**: Swift Package. Addons register into `AddonLoader` from their module initialisers.
