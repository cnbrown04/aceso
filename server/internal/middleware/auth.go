package middleware

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

type contextKey string

const userIDKey contextKey = "userID"

// DefaultUserID is the single self-hosted operator account.
const DefaultUserID = "default"

// Auth validates API keys and session tokens for dashboard and device clients.
type Auth struct {
	apiKey        string
	commandSecret []byte
	sessions      map[string]time.Time
	sessionsMu    sync.RWMutex
}

// NewAuth reads ACESO_API_KEY (defaults to "dev-api-key") and ACESO_COMMAND_SECRET.
func NewAuth() *Auth {
	key := os.Getenv("ACESO_API_KEY")
	if key == "" {
		key = "dev-api-key"
	}
	secret := os.Getenv("ACESO_COMMAND_SECRET")
	if secret == "" {
		secret = key
	}
	return &Auth{
		apiKey:        key,
		commandSecret: []byte(secret),
		sessions:      make(map[string]time.Time),
	}
}

// CommandSecret returns the HMAC key used to sign command envelopes.
func (a *Auth) CommandSecret() []byte {
	return a.commandSecret
}

// APIKey returns the configured dashboard API key.
func (a *Auth) APIKey() string {
	return a.apiKey
}

// HashToken returns a SHA-256 hex digest suitable for storage.
func (a *Auth) HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// IssueSession creates a random session token valid for 24 hours.
func (a *Auth) IssueSession() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	token := hex.EncodeToString(b)
	a.sessionsMu.Lock()
	a.sessions[token] = time.Now().Add(24 * time.Hour)
	a.sessionsMu.Unlock()
	return token
}

// ValidateSession returns true when the token is still valid.
func (a *Auth) ValidateSession(token string) bool {
	a.sessionsMu.RLock()
	exp, ok := a.sessions[token]
	a.sessionsMu.RUnlock()
	if !ok || time.Now().After(exp) {
		return false
	}
	return true
}

// UserIDFromContext returns the authenticated user id.
func UserIDFromContext(ctx context.Context) string {
	if v, ok := ctx.Value(userIDKey).(string); ok && v != "" {
		return v
	}
	return DefaultUserID
}

// WithUserID attaches a user id to the request context.
func WithUserID(ctx context.Context, userID string) context.Context {
	return context.WithValue(ctx, userIDKey, userID)
}

// bearerToken extracts the token from Authorization: Bearer <token>.
func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, "Bearer ") {
		return ""
	}
	return strings.TrimSpace(strings.TrimPrefix(h, "Bearer "))
}

// RequireAPIKey wraps a handler and rejects requests without a valid API key or session.
func (a *Auth) RequireAPIKey(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := bearerToken(r)
		if token == "" {
			token = r.Header.Get("X-API-Key")
		}
		if token == a.apiKey || a.ValidateSession(token) {
			next.ServeHTTP(w, r.WithContext(WithUserID(r.Context(), DefaultUserID)))
			return
		}
		http.Error(w, "unauthorized", http.StatusUnauthorized)
	})
}

// DeviceIDFromContext returns the device id set during device auth.
func DeviceIDFromContext(ctx context.Context) string {
	if v, ok := ctx.Value(contextKey("deviceID")).(string); ok {
		return v
	}
	return ""
}
