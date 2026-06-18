package remoteactions

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	server "github.com/aceso/server"
	"github.com/aceso/server/internal/db"
	"github.com/aceso/server/internal/live"
	"github.com/aceso/server/internal/middleware"
)

func init() {
	server.RegisterAddon(&Addon{})
}

type Addon struct{}

var (
	store db.RemoteStore
	hub   *live.Hub
	auth  *middleware.Auth
	apns  *middleware.APNSProvider
)

const commandTTL = 60 * time.Second

var allowedTypes = map[string]bool{
	"haptic.pattern4": true,
	"haptic.preset5":  true,
	"haptic.stop":     true,
	"alarm.set":       true,
	"alarm.disable":   true,
}

func (a *Addon) Register(deps *server.ServerDeps) error {
	store = deps.Store
	hub = deps.Hub
	auth = deps.Auth
	apns = deps.APNS

	hub.SetPresenceCallbacks(setDeviceOnline, setDeviceOffline)
	hub.SetDeviceMessageHandler(handleDeviceMessage)

	mux := deps.Mux
	protected := auth.RequireAPIKey

	mux.Handle("POST /api/auth/login", protected(http.HandlerFunc(handleLogin)))
	mux.Handle("POST /api/devices/register", protected(http.HandlerFunc(handleRegisterDevice)))
	mux.Handle("GET /api/devices", protected(http.HandlerFunc(handleListDevices)))
	mux.Handle("POST /api/commands", protected(http.HandlerFunc(handleCreateCommand)))
	mux.Handle("GET /api/commands/{id}", protected(http.HandlerFunc(handleGetCommand)))
	mux.Handle("GET /api/commands", protected(http.HandlerFunc(handleListCommands)))
	mux.Handle("PATCH /api/commands/{id}", http.HandlerFunc(handlePatchCommand))

	mux.Handle("GET /ws/device", hub.HandleDevice(authDevice))
	mux.Handle("GET /ws/live", hub.HandleLive(authUser))

	return nil
}

func authDevice(token string) (string, bool) {
	hash := auth.HashToken(token)
	d, ok := store.FindDeviceByTokenHash(hash)
	if !ok {
		return "", false
	}
	return d.ID, true
}

func authUser(token string) (string, bool) {
	if token == auth.APIKey() || auth.ValidateSession(token) {
		return middleware.DefaultUserID, true
	}
	return "", false
}

func handleLogin(w http.ResponseWriter, r *http.Request) {
	var body struct {
		APIKey string `json:"api_key"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.APIKey != auth.APIKey() {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	token := auth.IssueSession()
	writeJSON(w, http.StatusOK, map[string]string{"token": token})
}

func handleRegisterDevice(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DeviceID      string `json:"device_id"`
		Name          string `json:"name"`
		Platform      string `json:"platform"`
		WhoopDeviceID string `json:"whoop_device_id"`
		APNSToken     string `json:"apns_token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.DeviceID == "" {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}

	userID := middleware.UserIDFromContext(r.Context())
	plainToken, tokenHash := issueDeviceToken()

	device := db.Device{
		ID:            body.DeviceID,
		UserID:        userID,
		Name:          body.Name,
		Platform:      body.Platform,
		WhoopDeviceID: body.WhoopDeviceID,
		APNSToken:     body.APNSToken,
		Online:        hub.IsDeviceOnline(body.DeviceID),
		LastSeenAt:    time.Now().UTC(),
	}
	_ = store.SaveDevice(device)
	_ = store.SaveDeviceToken(body.DeviceID, tokenHash)

	writeJSON(w, http.StatusOK, map[string]any{
		"device":       device,
		"device_token": plainToken,
	})
}

func handleListDevices(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	devices := store.ListDevices(userID)
	for i := range devices {
		devices[i].Online = hub.IsDeviceOnline(devices[i].ID)
	}
	writeJSON(w, http.StatusOK, map[string]any{"devices": devices})
}

func handleCreateCommand(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DeviceID string          `json:"device_id"`
		Type     string          `json:"type"`
		Params   json.RawMessage `json:"params"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	if body.DeviceID == "" || !allowedTypes[body.Type] {
		http.Error(w, "invalid command", http.StatusBadRequest)
		return
	}
	if err := validateParams(body.Type, body.Params); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	userID := middleware.UserIDFromContext(r.Context())
	idemKey := r.Header.Get("Idempotency-Key")
	if idemKey != "" {
		if existing, ok := store.FindCommandByIdempotency(userID, idemKey); ok {
			writeJSON(w, http.StatusOK, existing)
			return
		}
	}

	device, ok := store.GetDevice(body.DeviceID)
	if !ok || device.UserID != userID {
		http.Error(w, "device not found", http.StatusNotFound)
		return
	}

	now := time.Now().UTC()
	cmd := db.Command{
		ID:             newID(),
		UserID:         userID,
		DeviceID:       body.DeviceID,
		Type:           body.Type,
		Params:         body.Params,
		Status:         db.CommandQueued,
		IdempotencyKey: idemKey,
		CreatedAt:      now,
		ExpiresAt:      now.Add(commandTTL),
	}
	_ = store.SaveCommand(cmd)
	broadcastCommand(cmd)

	envelope, err := signEnvelope(cmd)
	if err != nil {
		http.Error(w, "signing failed", http.StatusInternalServerError)
		return
	}

	if hub.PushCommand(body.DeviceID, envelope) {
		_ = store.UpdateCommandStatus(cmd.ID, db.CommandDelivered, nil)
		cmd.Status = db.CommandDelivered
		broadcastCommand(cmd)
	} else if device.APNSToken != "" {
		_ = apns.SendVisibleNotification(
			device.APNSToken,
			"Remote action pending",
			"Open Aceso to run a dashboard command.",
			cmd.ID,
		)
	}

	writeJSON(w, http.StatusCreated, cmd)
}

func handleGetCommand(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	cmd, ok := store.GetCommand(id)
	if !ok || cmd.UserID != middleware.UserIDFromContext(r.Context()) {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	writeJSON(w, http.StatusOK, cmd)
}

func handleListCommands(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	deviceID := r.URL.Query().Get("device_id")
	cmds := store.ListCommands(userID, deviceID, 50)
	writeJSON(w, http.StatusOK, map[string]any{"commands": cmds})
}

func handlePatchCommand(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	cmd, ok := store.GetCommand(id)
	if !ok {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}

	token := r.Header.Get("Authorization")
	if len(token) > 7 && token[:7] == "Bearer " {
		token = token[7:]
	}
	device, deviceOK := store.FindDeviceByTokenHash(auth.HashToken(token))
	if !deviceOK || device.ID != cmd.DeviceID {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	var body struct {
		Status string             `json:"status"`
		Result *db.CommandResult  `json:"result"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}

	status := db.CommandStatus(body.Status)
	switch status {
	case db.CommandExecuting, db.CommandCompleted, db.CommandFailed, db.CommandRejected:
	default:
		http.Error(w, "invalid status", http.StatusBadRequest)
		return
	}

	_ = store.UpdateCommandStatus(id, status, body.Result)
	cmd.Status = status
	cmd.Result = body.Result
	broadcastCommand(cmd)
	writeJSON(w, http.StatusOK, cmd)
}

func handleDeviceMessage(deviceID string, msg []byte) {
	var body struct {
		CommandID string            `json:"command_id"`
		Status    db.CommandStatus  `json:"status"`
		Result    *db.CommandResult `json:"result"`
	}
	if err := json.Unmarshal(msg, &body); err != nil || body.CommandID == "" {
		return
	}
	cmd, ok := store.GetCommand(body.CommandID)
	if !ok || cmd.DeviceID != deviceID {
		return
	}
	_ = store.UpdateCommandStatus(body.CommandID, body.Status, body.Result)
	cmd.Status = body.Status
	cmd.Result = body.Result
	broadcastCommand(cmd)
}

func setDeviceOnline(deviceID string) {
	_ = store.SetDeviceOnline(deviceID, true)
	d, ok := store.GetDevice(deviceID)
	if ok {
		broadcastPresence(d)
	}
}

func setDeviceOffline(deviceID string) {
	_ = store.SetDeviceOnline(deviceID, false)
	d, ok := store.GetDevice(deviceID)
	if ok {
		broadcastPresence(d)
	}
}

func broadcastCommand(cmd db.Command) {
	hub.BroadcastCommandEvent(cmd.UserID, map[string]any{
		"type":    "command",
		"command": cmd,
	})
}

func broadcastPresence(d db.Device) {
	hub.BroadcastCommandEvent(d.UserID, map[string]any{
		"type":   "presence",
		"device": d,
	})
}

func signEnvelope(cmd db.Command) ([]byte, error) {
	payload := map[string]any{
		"command_id": cmd.ID,
		"type":       cmd.Type,
		"params":     json.RawMessage(cmd.Params),
		"exp":        cmd.ExpiresAt.Unix(),
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	mac := hmac.New(sha256.New, auth.CommandSecret())
	mac.Write(raw)
	sig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	envelope := map[string]string{
		"payload":   base64.RawURLEncoding.EncodeToString(raw),
		"signature": sig,
	}
	return json.Marshal(envelope)
}

func validateParams(cmdType string, params json.RawMessage) error {
	switch cmdType {
	case "haptic.pattern4":
		var p struct {
			Pattern string `json:"pattern"`
			Loops   int    `json:"loops"`
		}
		if err := json.Unmarshal(params, &p); err != nil || p.Pattern == "" {
			return fmt.Errorf("invalid haptic.pattern4 params")
		}
	case "haptic.preset5":
		var p struct {
			Preset string `json:"preset"`
		}
		if err := json.Unmarshal(params, &p); err != nil || p.Preset == "" {
			return fmt.Errorf("invalid haptic.preset5 params")
		}
	case "haptic.stop", "alarm.disable":
		if len(params) == 0 {
			params = json.RawMessage(`{}`)
		}
	case "alarm.set":
		var p struct {
			FireAtISO string `json:"fire_at_iso"`
		}
		if err := json.Unmarshal(params, &p); err != nil || p.FireAtISO == "" {
			return fmt.Errorf("invalid alarm.set params")
		}
	}
	return nil
}

func issueDeviceToken() (plain, hash string) {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	plain = hex.EncodeToString(b)
	hash = auth.HashToken(plain)
	return plain, hash
}

func newID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// Exposed for tests.
func VerifyEnvelope(payloadB64, signature string, secret []byte) (map[string]any, bool) {
	raw, err := base64.RawURLEncoding.DecodeString(payloadB64)
	if err != nil {
		return nil, false
	}
	mac := hmac.New(sha256.New, secret)
	mac.Write(raw)
	expected := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(expected), []byte(signature)) {
		return nil, false
	}
	var payload map[string]any
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil, false
	}
	return payload, true
}

// AllowedCommandTypes returns the v1 allowlist.
func AllowedCommandTypes() []string {
	out := make([]string, 0, len(allowedTypes))
	for k := range allowedTypes {
		out = append(out, k)
	}
	return out
}

