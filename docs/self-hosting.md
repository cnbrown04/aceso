# Self-Hosting

## Quick start (Docker)

```bash
git clone https://github.com/your-org/aceso
cd aceso
make docker-up
```

The server is now listening on `http://localhost:8080`.

## Local development

**Server**
```bash
make dev-server
```

**Web**
```bash
make dev-web   # http://localhost:5173
```

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | (SQLite in-memory) | Postgres DSN, or omit for SQLite |
| `PORT` | `8080` | HTTP listen port |

## Enabling addons

Addons are opt-in. To enable a server addon, blank-import its package in `server/cmd/server/main.go`:

```go
import _ "github.com/aceso/server/addons/notifications/server"
```
