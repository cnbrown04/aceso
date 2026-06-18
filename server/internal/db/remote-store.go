package db

import (
	"encoding/json"
	"sync"
	"time"
)

// CommandStatus is the lifecycle state of a remote command.
type CommandStatus string

const (
	CommandQueued    CommandStatus = "queued"
	CommandDelivered CommandStatus = "delivered"
	CommandExecuting CommandStatus = "executing"
	CommandCompleted CommandStatus = "completed"
	CommandFailed    CommandStatus = "failed"
	CommandRejected  CommandStatus = "rejected"
	CommandExpired   CommandStatus = "expired"
)

// Device represents a registered iOS client.
type Device struct {
	ID            string    `json:"id"`
	UserID        string    `json:"user_id"`
	Name          string    `json:"name"`
	Platform      string    `json:"platform"`
	WhoopDeviceID string    `json:"whoop_device_id,omitempty"`
	APNSToken     string    `json:"apns_token,omitempty"`
	Online        bool      `json:"online"`
	LastSeenAt    time.Time `json:"last_seen_at"`
}

// CommandResult captures the outcome reported by the iOS executor.
type CommandResult struct {
	Message string `json:"message,omitempty"`
	Code    string `json:"code,omitempty"`
}

// Command is a short-lived remote action queued for a device.
type Command struct {
	ID             string          `json:"id"`
	UserID         string          `json:"user_id"`
	DeviceID       string          `json:"device_id"`
	Type           string          `json:"type"`
	Params         json.RawMessage `json:"params"`
	Status         CommandStatus   `json:"status"`
	IdempotencyKey string          `json:"idempotency_key,omitempty"`
	CreatedAt      time.Time       `json:"created_at"`
	ExpiresAt      time.Time       `json:"expires_at"`
	Result         *CommandResult  `json:"result,omitempty"`
}

// DeviceToken binds a bearer credential to a device.
type DeviceToken struct {
	DeviceID  string
	TokenHash string
	CreatedAt time.Time
}

// RemoteStore persists devices, tokens, and commands.
type RemoteStore interface {
	// Devices
	SaveDevice(d Device) error
	GetDevice(id string) (Device, bool)
	ListDevices(userID string) []Device
	SetDeviceOnline(id string, online bool) error
	UpdateDeviceAPNSToken(id, token string) error

	// Device tokens
	SaveDeviceToken(deviceID, tokenHash string) error
	FindDeviceByTokenHash(hash string) (Device, bool)

	// Commands
	SaveCommand(c Command) error
	GetCommand(id string) (Command, bool)
	UpdateCommandStatus(id string, status CommandStatus, result *CommandResult) error
	ListCommands(userID, deviceID string, limit int) []Command
	FindCommandByIdempotency(userID, key string) (Command, bool)
}

type memoryRemoteStore struct {
	mu      sync.RWMutex
	devices map[string]Device
	tokens  map[string]string // hash -> deviceID
	cmds    map[string]Command
}

// NewMemoryRemoteStore returns an in-memory RemoteStore for development.
func NewMemoryRemoteStore() RemoteStore {
	return &memoryRemoteStore{
		devices: make(map[string]Device),
		tokens:  make(map[string]string),
		cmds:    make(map[string]Command),
	}
}

func (s *memoryRemoteStore) SaveDevice(d Device) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.devices[d.ID] = d
	return nil
}

func (s *memoryRemoteStore) GetDevice(id string) (Device, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	d, ok := s.devices[id]
	return d, ok
}

func (s *memoryRemoteStore) ListDevices(userID string) []Device {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Device, 0)
	for _, d := range s.devices {
		if d.UserID == userID {
			out = append(out, d)
		}
	}
	return out
}

func (s *memoryRemoteStore) SetDeviceOnline(id string, online bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.devices[id]
	if !ok {
		return nil
	}
	d.Online = online
	d.LastSeenAt = time.Now().UTC()
	s.devices[id] = d
	return nil
}

func (s *memoryRemoteStore) UpdateDeviceAPNSToken(id, token string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.devices[id]
	if !ok {
		return nil
	}
	d.APNSToken = token
	s.devices[id] = d
	return nil
}

func (s *memoryRemoteStore) SaveDeviceToken(deviceID, tokenHash string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.tokens[tokenHash] = deviceID
	return nil
}

func (s *memoryRemoteStore) FindDeviceByTokenHash(hash string) (Device, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	deviceID, ok := s.tokens[hash]
	if !ok {
		return Device{}, false
	}
	d, ok := s.devices[deviceID]
	return d, ok
}

func (s *memoryRemoteStore) SaveCommand(c Command) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cmds[c.ID] = c
	return nil
}

func (s *memoryRemoteStore) GetCommand(id string) (Command, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	c, ok := s.cmds[id]
	return c, ok
}

func (s *memoryRemoteStore) UpdateCommandStatus(id string, status CommandStatus, result *CommandResult) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	c, ok := s.cmds[id]
	if !ok {
		return nil
	}
	c.Status = status
	c.Result = result
	s.cmds[id] = c
	return nil
}

func (s *memoryRemoteStore) ListCommands(userID, deviceID string, limit int) []Command {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Command, 0)
	for _, c := range s.cmds {
		if c.UserID != userID {
			continue
		}
		if deviceID != "" && c.DeviceID != deviceID {
			continue
		}
		out = append(out, c)
	}
	if limit > 0 && len(out) > limit {
		out = out[len(out)-limit:]
	}
	return out
}

func (s *memoryRemoteStore) FindCommandByIdempotency(userID, key string) (Command, bool) {
	if key == "" {
		return Command{}, false
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, c := range s.cmds {
		if c.UserID == userID && c.IdempotencyKey == key {
			return c, true
		}
	}
	return Command{}, false
}
