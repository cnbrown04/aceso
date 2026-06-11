package main

import (
	"log"
	"net/http"

	addonloader "github.com/aceso/server"
	"github.com/aceso/server/internal/db"
	"github.com/aceso/server/internal/ingest"
)

func main() {
	addonloader.LoadAll()

	mux := http.NewServeMux()

	store := db.NewMemoryStore()
	ingest.New(store).Register(mux)

	log.Println("server listening on :8080")
	if err := http.ListenAndServe(":8080", mux); err != nil {
		log.Fatal(err)
	}
}
