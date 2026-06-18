package remoteactions_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	addonloader "github.com/aceso/server"
	"github.com/aceso/server/internal/db"
	"github.com/aceso/server/internal/live"
	"github.com/aceso/server/internal/middleware"
	"github.com/aceso/server/internal/remoteactions"
)

func newTestMux(t *testing.T) (*http.ServeMux, *middleware.Auth) {
	t.Helper()
	mux := http.NewServeMux()
	auth := middleware.NewAuth()
	deps := &addonloader.ServerDeps{
		Mux:   mux,
		Store: db.NewMemoryRemoteStore(),
		Hub:   live.NewHub(),
		Auth:  auth,
		APNS:  middleware.NewAPNSProvider(),
	}
	if err := (&remoteactions.Addon{}).Register(deps); err != nil {
		t.Fatal(err)
	}
	return mux, auth
}

func TestCreateCommandRequiresAuth(t *testing.T) {
	mux, _ := newTestMux(t)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	body, _ := json.Marshal(map[string]any{
		"device_id": "phone-1",
		"type":      "haptic.stop",
		"params":    map[string]any{},
	})
	res, err := http.Post(srv.URL+"/api/commands", "application/json", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", res.StatusCode)
	}
}

func TestRegisterDeviceAndCreateCommand(t *testing.T) {
	mux, auth := newTestMux(t)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	regBody, _ := json.Marshal(map[string]any{
		"device_id": "phone-1",
		"name":      "Test iPhone",
		"platform":  "ios",
	})
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/devices/register", bytes.NewReader(regBody))
	req.Header.Set("Authorization", "Bearer "+auth.APIKey())
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("register: expected 200, got %d", res.StatusCode)
	}

	cmdBody, _ := json.Marshal(map[string]any{
		"device_id": "phone-1",
		"type":      "haptic.preset5",
		"params":    map[string]string{"preset": "notify"},
	})
	req, _ = http.NewRequest(http.MethodPost, srv.URL+"/api/commands", bytes.NewReader(cmdBody))
	req.Header.Set("Authorization", "Bearer "+auth.APIKey())
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusCreated {
		t.Fatalf("command: expected 201, got %d", res.StatusCode)
	}

	var cmd db.Command
	if err := json.NewDecoder(res.Body).Decode(&cmd); err != nil {
		t.Fatal(err)
	}
	if cmd.Status != db.CommandQueued {
		t.Fatalf("expected queued, got %s", cmd.Status)
	}
}

func TestVerifyEnvelopeRejectsBadSignature(t *testing.T) {
	auth := middleware.NewAuth()
	rawB64 := "eyJjb21tYW5kX2lkIjoiYWJjIiwidHlwZSI6ImhhcHRpYy5zdG9wIiwicGFyYW1zIjp7fSwiZXhwIjo5OTk5OTk5OTk5fQ"
	_, ok := remoteactions.VerifyEnvelope(rawB64, "bad", auth.CommandSecret())
	if ok {
		t.Fatal("expected invalid signature")
	}
}
