# Aceso — Agent Guide

This file is the single source of truth for any agent (AI or human) working in this repository. Read it before touching anything. The full detail behind each rule lives in `docs/conventions.md`.

## First-time setup

Install `pre-commit` (once per machine), then install the hooks into your clone:

```bash
brew install pre-commit   # or: pip install pre-commit
make install-hooks
```

This enables two hooks:
- **pre-commit** — gitleaks scans staged files for secrets before every commit
- **commit-msg** — gitlint rejects commits whose message does not follow Conventional Commits

**Conventional Commits format:** `<type>(<scope>): <description>`

```
feat(ios): add recovery dashboard
fix: handle nil session on startup
chore(ci)!: drop Node 18 support
```

Allowed types: `build` `chore` `ci` `docs` `feat` `fix` `perf` `refactor` `revert` `style` `test`

Configuration lives in `.gitlint` at the repo root.

---

## What this project is

Aceso is a self-hosted health-tracking platform. It consists of:

- `apps/ios/` — native SwiftUI iOS app
- `apps/web/` — TanStack Start (React, SSR) web dashboard
- `server/` — Go HTTP server (data ingest, API, live updates)
- `addons/` — optional feature packages that can be dropped into any of the three platforms

The three platforms communicate over HTTP and WebSockets. The server is the source of truth for all data. The iOS app and web dashboard are clients.

---

## Repo layout

```
Aceso/
├── addons/               all addons live here, never inside apps/
│   ├── _template/        copy this to start a new addon
│   └── <addon-name>/
│       ├── addon.json    required manifest
│       ├── ios/          Swift package (optional)
│       ├── web/          npm package (optional)
│       └── server/       Go module (optional)
├── apps/
│   ├── ios/              Xcode project
│   └── web/              TanStack Start app
├── server/               Go server
├── docker/               Dockerfile + docker-compose.yml
├── docs/                 architecture, conventions, addon guide, self-hosting
├── .github/workflows/    ci.yml, release.yml
├── Makefile
└── AGENTS.md             ← you are here
```

---

## Naming — one rule, no exceptions by language

**Every file and folder uses `kebab-case`.** This applies to Go, Swift, TypeScript, CSS, YAML, everything.

```
addon-loader.go          ✓
addon-loader.swift       ✓
theme-toggle.tsx         ✓

AddonLoader.go           ✗
addon_loader.go          ✗
ThemeToggle.tsx          ✗
```

Identifiers *inside* files (type names, function names, variables) still follow each language's own rules. Only the filename itself is governed by kebab-case.

### Forced exceptions — do not rename these

| Name | Forced by |
|---|---|
| `README.md`, `AGENTS.md` | Convention — tools and GitHub look for these exact names |
| `Makefile`, `Dockerfile` | `make` and Docker require exact casing |
| `Package.swift` | Swift Package Manager |
| `go.mod`, `go.sum`, `main.go` | Go toolchain |
| `*_test.go` | Go — the `_test.go` suffix is how the toolchain identifies test files |
| `package.json` | npm |
| `__root.tsx`, `routeTree.gen.ts` | TanStack Router (codegen) |
| `vite.config.ts`, `tsconfig.json`, `tsr.config.json`, `playwright.config.ts` | Tool config files |
| `Aceso/`, `AcesoTests/`, `AcesoUITests/`, `Aceso.xcodeproj/` | Hardcoded in Xcode's `project.pbxproj` |

---

## Folder structure

Organise by feature first, then by role within that feature. Never organise by type across features (no top-level `models/`, `views/`, `controllers/`).

**Web** (`apps/web/src/`)
```
src/
├── components/
│   ├── layout/      shell components: header, footer, sidebar
│   └── ui/          generic primitives: button, badge, theme-toggle
├── lib/             non-React utilities: api.ts, ws.ts
├── routes/          TanStack Router file routes — tool-managed, do not reorganise
├── addon-loader.ts
└── router.tsx
```

**iOS** (`apps/ios/Aceso/`)
```
Aceso/
├── screens/
│   ├── recovery/
│   ├── sleep/
│   └── strain/
├── shared/
│   ├── components/
│   ├── extensions/
│   └── models/
└── addon-loader.swift
```

**Server** (`server/`)
```
server/
├── cmd/server/          entry point (main.go)
├── internal/
│   ├── api/
│   ├── db/
│   ├── ingest/
│   ├── live/
│   └── middleware/
├── e2e/                 e2e tests (build tag: e2e)
└── addon-loader.go
```

---

## Comments

Write **why**, not what. If the code already makes the intent clear, the comment is noise.

```go
// retry up to 3 times — BLE stack drops the first write during pairing
```

- **Go**: doc comments on exported symbols only. Start with the symbol name.
- **Swift**: `///` on `public` types and functions only.
- **TypeScript**: JSDoc only on exported functions where the signature alone isn't enough.

Never write comments that restate the function name, describe obvious logic, or reference a PR or issue number.

---

## Imports

Always three groups, blank line between them. Never mix groups.

**Go** — stdlib → third-party → internal:
```go
import (
    "context"
    "net/http"

    "github.com/some/library"

    "github.com/aceso/server/internal/db"
)
```

**Swift** — system frameworks → internal modules:
```swift
import SwiftUI
import HealthKit

import AcesoCore
```

**TypeScript** — external packages → `#/` internal aliases → relative paths:
```ts
import { createFileRoute } from '@tanstack/react-router'

import { get } from '#/lib/api'

import MyComponent from './my-component'
```

---

## Testing

Every layer has its own test type. Do not skip a layer or test at the wrong level.

### Web

| Type | Tool | Location | Run |
|---|---|---|---|
| Unit | Vitest | alongside source | `make test-web` |
| E2E | Playwright | `apps/web/e2e/` | `make test-e2e` |

Playwright drives a real browser against a live dev server. Tests live in `apps/web/e2e/` and are named `<feature>.spec.ts`. The CI job posts a summary comment on every PR.

### Server (Go)

| Type | Tool | Location | Run |
|---|---|---|---|
| Unit | `go test` | `*_test.go` alongside source | `make test-server` |
| E2E | `go test -tags=e2e` | `server/e2e/` | `make test-server-e2e` |

Go E2E tests use `//go:build e2e` at the top of the file and `net/http/httptest` to test against a real handler mux. They never run during normal `go test ./...`.

### iOS

| Type | Tool | Location | Run |
|---|---|---|---|
| Build check | `xcodebuild build` | — | `make build-ios` |
| Unit | Swift Testing | `AcesoTests/` | via Xcode or CI |
| UI | XCUITest | `AcesoUITests/` | via Xcode or CI |

**After every iOS change, run the build check before considering the task done:**

```bash
xcodebuild build \
  -project apps/ios/Aceso.xcodeproj \
  -scheme Aceso \
  -destination 'generic/platform=iOS Simulator' \
  -quiet
```

A zero exit code means the project compiles cleanly. Fix any errors before reporting success.

XCUITest launches the real app in a simulator and drives it through the accessibility layer. It is the iOS equivalent of Playwright. UI tests require a macOS runner in CI (10× the cost of Linux — keep them lean).

---

## Addons

Every addon lives entirely under `addons/<addon-name>/`. Apps never contain addon code.

Each addon must have an `addon.json` manifest at its root:

```jsonc
{
  "id": "addon-name",          // kebab-case, unique
  "name": "Display Name",
  "version": "0.1.0",          // semver
  "description": "What problem it solves.",
  "platforms": ["ios"],        // which of ios / web / server it ships code for
  "hooks": {
    "ios": "What it registers in AddonLoader and when."
  },
  "aceso": "0.1.0",            // minimum compatible Aceso version
  "author": ""
}
```

Each platform sub-directory is an independent package:

| Platform | Entry file | Registration |
|---|---|---|
| iOS | any `.swift` file | call `AddonLoader.shared.register(...)` from a stored-property initialiser |
| Web | `index.ts` default export | picked up at build time by `import.meta.glob` in `src/addon-loader.ts` |
| Server | any `.go` file | call `server.RegisterAddon(...)` from `func init()` |

Copy `addons/_template/` to start. Delete platform sub-directories you don't need.

---

## GitHub Actions / CI

### What runs on every PR

All four of these checks must pass before a PR can merge (enforced by branch protection on `main`):

| Check name | What it does |
|---|---|
| `Go (unit)` | `go build` + `go test ./...` |
| `Go (e2e)` | `go test -tags=e2e ./e2e/...` |
| `Web (build + unit)` | `npm run build` + `npm test` |
| `Web (e2e)` | Playwright — posts a result summary comment on the PR |
| `iOS (unit)` | `xcodebuild test -only-testing:AcesoTests` on iOS Simulator |
| `iOS (UI)` | `xcodebuild test -only-testing:AcesoUITests` on iOS Simulator |

### Security rules — never violate these

These rules exist because of how the TanStack supply chain attack worked in May 2026. The attacker used `pull_request_target` to run fork code in the base repo's trusted context, poisoned the Actions cache, then extracted an OIDC token from runner memory to publish malicious npm packages.

1. **Never use `pull_request_target`**. Use `pull_request` only. `pull_request_target` runs fork code with base-repo permissions — that was the attack's entry point.
2. **Pin every action to a full commit SHA**, not a tag. Tags are mutable and can be silently moved. The SHA goes in a comment next to the action: `uses: actions/checkout@abc123 # v4`.
3. **`permissions: contents: read` at the top of every workflow**. Grant write permissions only in the specific job that needs them.
4. **`persist-credentials: false` on every `actions/checkout` step**.
5. **Never interpolate `${{ github.event.* }}` directly inside a `run:` shell script**. Put it in an `env:` block first to prevent shell injection.

When adding a new action to a workflow, fetch its current SHA with:
```bash
gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq '.object.sha'
```

---

## What not to do

- Do not create files with `PascalCase`, `snake_case`, or `camelCase` names. Use `kebab-case`.
- Do not add features, abstractions, or error handling beyond what the task requires.
- Do not write comments that explain what code does — only why it does something non-obvious.
- Do not edit `apps/web/src/routeTree.gen.ts` — it is auto-generated by TanStack Router.
- Do not place addon code inside `apps/`. All addon code lives in `addons/`.
- Do not use `pull_request_target` in any GitHub Actions workflow.
- Do not reference action tags (`@v4`) without pinning to a SHA.
- Do not run `kubectl`, `helm`, or other cluster tools directly — print the command for the operator to run.
- Do not read or commit `.env` files, credentials, or secrets.
- Do not amend published commits. Create a new commit instead.

---

## iOS-specific: WHOOP BLE pairing

WHOOP 4.0 uses a **BLE Filter Accept List (FAL)**: after initial bonding, the strap only accepts L2CAP connections from device Bluetooth addresses it has previously bonded with. If Aceso discovers the WHOOP (it appears in scan results) but `didConnect` never fires, the iPhone's BT address is not in the WHOOP's filter — this typically happens when the strap was last bonded to a different device.

**How `WhoopBLEClient` handles this:** after 2 consecutive connect timeouts where the WHOOP was visible, it sets `connectionError` and surfaces a message telling the user to enter pairing mode. Auto-retry stops; the user must tap Retry after clearing the condition.

**WHOOP pairing mode:** repeatedly tap the top of the WHOOP 4.0 (the hard sensor side). This clears the filter accept list and lets any device initiate a fresh just-works bond. The user does **not** need the official WHOOP app — pairing mode is sufficient.

**Bond write rejection (`didWriteValueFor` "Encryption is insufficient"):** means the strap accepted the connection but refused the bond because it still holds an LTK from a different device. The user must enter pairing mode on the WHOOP (button hold) and then tap Retry in Aceso.

---

## Web-specific: TanStack Router skills

`apps/web/AGENTS.md` contains TanStack Intent skill mappings for TanStack Router and Start patterns. Read it when working on routing, server functions, SSR, or auth in the web app.
