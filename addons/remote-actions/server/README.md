# Remote Actions — server

Go implementation lives in [`server/internal/remoteactions/`](../../../server/internal/remoteactions/) because Go `internal/` packages must stay within the main server module.

The addon registers via `init()` and is blank-imported from [`server/cmd/server/main.go`](../../../server/cmd/server/main.go).
