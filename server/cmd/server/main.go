package main

import (
	"log"
	"net/http"

	addonloader "github.com/aceso/server"
)

func main() {
	addonloader.LoadAll()

	mux := http.NewServeMux()
	// routes registered here

	log.Println("server listening on :8080")
	if err := http.ListenAndServe(":8080", mux); err != nil {
		log.Fatal(err)
	}
}
