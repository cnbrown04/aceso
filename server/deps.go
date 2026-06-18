package server

import (
	"net/http"

	"github.com/aceso/server/internal/db"
	"github.com/aceso/server/internal/live"
	"github.com/aceso/server/internal/middleware"
)

// ServerDeps bundles shared services passed to every server addon at registration time.
type ServerDeps struct {
	Mux      *http.ServeMux
	Store    db.RemoteStore
	Hub      *live.Hub
	Auth     *middleware.Auth
	APNS     *middleware.APNSProvider
	CORSOrig string
}
