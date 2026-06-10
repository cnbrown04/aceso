# Conventions

Rules that apply across the whole repo. When something isn't covered here, match the style of the surrounding code.

---

## Naming — one rule for everything

**All files and folders use `kebab-case`.**

This applies to every language — Go, Swift, TypeScript, everything. No exceptions based on language idiom.

```
addon-loader.go          ✓
addon-loader.swift       ✓
theme-toggle.tsx         ✓
apple-health-addon.swift ✓

AddonLoader.go           ✗
addon_loader.go          ✗
ThemeToggle.tsx          ✗
```

The names of types, functions, and variables inside files still follow each language's own rules (e.g. `PascalCase` for Swift/TS types, `camelCase` for Go exports). Only the filename is governed by this rule.

### Forced exceptions

These names are dictated by a tool and cannot be changed without breaking something:

| File or folder | Forced by | Why it can't change |
|---|---|---|
| `Package.swift` | Swift Package Manager | SPM looks for this exact filename |
| `go.mod`, `go.sum` | Go toolchain | Required by spec |
| `main.go` | Go entry point convention | `go run ./cmd/server` expects this |
| `package.json` | npm | Required by spec |
| `__root.tsx` | TanStack Router | Router codegen looks for this name |
| `routeTree.gen.ts` | TanStack Router codegen | Auto-generated, name is hardcoded |
| `vite.config.ts`, `tsconfig.json`, `tsr.config.json` | Tool config | Each tool looks for these exact names |
| `Aceso/`, `AcesoTests/`, `AcesoUITests/` | Xcode `.xcodeproj` | Folder paths are hardcoded in `project.pbxproj` |
| `Aceso.xcodeproj/` | Xcode | The project file itself |

### Files that look forced but aren't

Xcode generates `AcesoApp.swift`, `ContentView.swift`, `AcesoTests.swift`, `AcesoUITests.swift`, and `AcesoUITestsLaunchTests.swift` with PascalCase names, but these are **not** referenced by filename in `project.pbxproj` — Xcode tracks files by UUID. They can be renamed using Xcode's **Refactor → Rename** on the type name, which renames the file in sync. These should be renamed to `kebab-case` when convenient.

---

## Folders

Organised by feature at the top level, then by role within each feature. Shared or cross-cutting code gets its own `shared/` or `lib/` directory at the appropriate level.

**Web** (`apps/web/src/`)
```
src/
├── components/
│   ├── layout/      ← shell: header, footer, sidebar
│   └── ui/          ← generic primitives: theme-toggle, button, badge
├── lib/             ← non-React utilities: api.ts, ws.ts
├── routes/          ← TanStack Router file routes (tool-managed)
├── addon-loader.ts
└── router.tsx
```

**iOS** (`apps/ios/Aceso/`)
```
Aceso/                    ← Xcode-managed name, cannot change
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
├── cmd/server/      ← entry point
├── internal/
│   ├── api/
│   ├── db/
│   ├── ingest/
│   ├── live/
│   └── middleware/
└── addon-loader.go
```

---

## Addon manifest

Every addon must have an `addon.json` at its root (alongside the `ios/`, `web/`, `server/` sub-directories). This is the single source of truth for what the addon is, what it does, and where it plugs in. It is machine-readable so a future registry or installer can consume it without parsing README prose.

```
addons/
└── my-addon/
    ├── addon.json       ← required
    ├── ios/
    ├── web/
    └── server/
```

### Fields

```jsonc
{
  // Unique identifier. kebab-case, no spaces, no "aceso" prefix.
  "id": "apple-health",

  // Human-readable display name.
  "name": "Apple Health",

  // Semantic version of this addon.
  "version": "0.1.0",

  // One or two sentences: what problem it solves.
  "description": "Writes recovery, strain, and sleep metrics to Apple HealthKit after each sync.",

  // Which platform sub-directories this addon actually ships code for.
  "platforms": ["ios"],

  // What the addon hooks into on each platform. Free-form but be specific.
  "hooks": {
    "ios": "Registers with AddonLoader and requests HealthKit write authorisation on first activation.",
    "server": "Adds a POST /api/webhooks/notifications route and fires outbound requests on low-recovery events."
  },

  // Minimum Aceso version this addon is compatible with.
  "aceso": "0.1.0",

  // Who wrote it.
  "author": "your name or handle"
}
```

`id`, `name`, `version`, `description`, `platforms`, and `aceso` are required. `hooks` and `author` are optional but strongly encouraged.

### Existing addon manifests

See each addon directory for its `addon.json`. The `_template` addon's manifest is the canonical starting point for new addons.

---

## Comments

Write comments that explain **why**, not what. If the code itself makes the intent obvious, the comment is noise.

```go
// retry up to 3 times — BLE stack drops the first write during pairing
for range 3 {
    err = write(packet)
}
```

**Go** — doc comments on exported symbols only, starting with the symbol name:
```go
// RegisterAddon enrolls an addon in the registry. Not safe for concurrent use.
func RegisterAddon(a Addon) { ... }
```

**Swift** — `///` doc comments on `public` types and functions only:
```swift
/// Activates all registered addons. Call once before any UI is shown.
public func activateAll() { ... }
```

**TypeScript** — JSDoc only on exported functions where the signature alone isn't enough:
```ts
/** Opens a persistent WebSocket. Caller must call ws.close() on unmount. */
export function connect(path: string, onMessage: (data: unknown) => void): WebSocket
```

Never comment obvious logic, restate the function name, or reference the PR/issue that introduced the code.

---

## Imports

Keep a consistent order. Group by origin, blank line between groups.

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

**TypeScript** — external packages → internal aliases (`#/*`) → relative:
```ts
import { createFileRoute } from '@tanstack/react-router'

import { get } from '#/lib/api'

import SomeLocalComponent from './some-local-component'
```

---

## Platform package files

Each platform sub-directory within an addon is an independent package. The package file names are tool-forced and cannot change:

| Platform | Package file | Name pattern |
|---|---|---|
| iOS | `Package.swift` | SPM library named `<AddonName>Addon` |
| Web | `package.json` | npm name `@aceso/addon-<name>` |
| Server | `go.mod` | module `github.com/aceso/addon-<name>` |
