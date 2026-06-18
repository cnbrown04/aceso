package main

import (
	"log"
	"net/http"
	"os"
	"time"

	addonloader "github.com/aceso/server"
	"github.com/aceso/server/internal/db"
	"github.com/aceso/server/internal/ingest"
	"github.com/aceso/server/internal/live"
	"github.com/aceso/server/internal/middleware"

	_ "github.com/aceso/server/internal/remoteactions"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	whoopStore := db.NewMemoryStore()
	remoteStore := db.NewMemoryRemoteStore()
	hub := live.NewHub()
	auth := middleware.NewAuth()
	apns := middleware.NewAPNSProvider()
	corsOrigin := middleware.AllowedOriginFromEnv(os.Getenv("ACESO_CORS_ORIGIN"))

	deps := &addonloader.ServerDeps{
		Mux:      mux,
		Store:    remoteStore,
		Hub:      hub,
		Auth:     auth,
		APNS:     apns,
		CORSOrig: corsOrigin,
	}
	addonloader.LoadAll(deps)

	ingest.New(whoopStore).Register(mux)

	handler := middleware.Chain(
		mux,
		middleware.CORS(corsOrigin),
		middleware.NewRateLimiter(60, time.Minute).Limit,
	)

	addr := ":" + port
	log.Println("server listening on", addr)
	if err := http.ListenAndServe(addr, handler); err != nil {
		log.Fatal(err)
	}
}
