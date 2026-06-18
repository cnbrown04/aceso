package live

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

// Hub routes WebSocket messages between dashboard clients and registered devices.
type Hub struct {
	mu          sync.RWMutex
	devices     map[string]*deviceConn
	liveClients map[*liveConn]struct{}
}

type deviceConn struct {
	deviceID string
	conn     *websocket.Conn
	send     chan []byte
}

type liveConn struct {
	userID string
	conn   *websocket.Conn
	send   chan []byte
}

// NewHub creates an empty connection hub.
func NewHub() *Hub {
	return &Hub{
		devices:     make(map[string]*deviceConn),
		liveClients: make(map[*liveConn]struct{}),
	}
}

// IsDeviceOnline reports whether a device WebSocket is connected.
func (h *Hub) IsDeviceOnline(deviceID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	_, ok := h.devices[deviceID]
	return ok
}

// PushCommand delivers a signed command envelope to a connected device.
func (h *Hub) PushCommand(deviceID string, payload []byte) bool {
	h.mu.RLock()
	dc, ok := h.devices[deviceID]
	h.mu.RUnlock()
	if !ok {
		return false
	}
	select {
	case dc.send <- payload:
		return true
	default:
		return false
	}
}

// BroadcastCommandEvent notifies dashboard subscribers of command lifecycle changes.
func (h *Hub) BroadcastCommandEvent(userID string, event any) {
	data, err := json.Marshal(event)
	if err != nil {
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for lc := range h.liveClients {
		if lc.userID != userID {
			continue
		}
		select {
		case lc.send <- data:
		default:
		}
	}
}

// HandleDevice serves GET /ws/device for iOS clients.
func (h *Hub) HandleDevice(authDevice func(token string) (deviceID string, ok bool)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := bearerToken(r)
		deviceID, ok := authDevice(token)
		if !ok {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}

		dc := &deviceConn{
			deviceID: deviceID,
			conn:     conn,
			send:     make(chan []byte, 16),
		}

		h.mu.Lock()
		if old, exists := h.devices[deviceID]; exists {
			close(old.send)
			_ = old.conn.Close()
		}
		h.devices[deviceID] = dc
		h.mu.Unlock()

		onConnect(deviceID)
		defer func() {
			h.mu.Lock()
			if cur, exists := h.devices[deviceID]; exists && cur == dc {
				delete(h.devices, deviceID)
			}
			h.mu.Unlock()
			onDisconnect(deviceID)
			close(dc.send)
			_ = conn.Close()
		}()

		go writePump(conn, dc.send)
		h.readDevicePump(dc)
	}
}

// HandleLive serves GET /ws/live for dashboard clients.
func (h *Hub) HandleLive(authUser func(token string) (userID string, ok bool)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := bearerToken(r)
		userID, ok := authUser(token)
		if !ok {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}

		lc := &liveConn{
			userID: userID,
			conn:   conn,
			send:   make(chan []byte, 16),
		}

		h.mu.Lock()
		h.liveClients[lc] = struct{}{}
		h.mu.Unlock()

		defer func() {
			h.mu.Lock()
			delete(h.liveClients, lc)
			h.mu.Unlock()
			close(lc.send)
			_ = conn.Close()
		}()

		go writePump(conn, lc.send)
		h.readLivePump(lc)
	}
}

var (
	onConnect    = func(string) {}
	onDisconnect = func(string) {}
)

// SetPresenceCallbacks wires device online/offline hooks (used by remote-actions addon).
func (h *Hub) SetPresenceCallbacks(connect, disconnect func(deviceID string)) {
	onConnect = connect
	onDisconnect = disconnect
}

func (h *Hub) readDevicePump(dc *deviceConn) {
	dc.conn.SetReadDeadline(time.Now().Add(90 * time.Second))
	dc.conn.SetPongHandler(func(string) error {
		dc.conn.SetReadDeadline(time.Now().Add(90 * time.Second))
		return nil
	})
	for {
		_, msg, err := dc.conn.ReadMessage()
		if err != nil {
			return
		}
		h.handleDeviceMessage(dc.deviceID, msg)
	}
}

func (h *Hub) readLivePump(lc *liveConn) {
	lc.conn.SetReadDeadline(time.Now().Add(90 * time.Second))
	lc.conn.SetPongHandler(func(string) error {
		lc.conn.SetReadDeadline(time.Now().Add(90 * time.Second))
		return nil
	})
	for {
		if _, _, err := lc.conn.ReadMessage(); err != nil {
			return
		}
	}
}

func writePump(conn *websocket.Conn, send <-chan []byte) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case msg, ok := <-send:
			if !ok {
				_ = conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			_ = conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			_ = conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

type deviceMessageHandler func(deviceID string, msg []byte)

var deviceMsgHandler deviceMessageHandler = func(deviceID string, msg []byte) {
	log.Printf("live: unhandled device message from %s: %s", deviceID, string(msg))
}

// SetDeviceMessageHandler processes inbound messages from iOS (status updates).
func (h *Hub) SetDeviceMessageHandler(fn deviceMessageHandler) {
	deviceMsgHandler = fn
}

func (h *Hub) handleDeviceMessage(deviceID string, msg []byte) {
	deviceMsgHandler(deviceID, msg)
}

func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if len(h) > 7 && h[:7] == "Bearer " {
		return h[7:]
	}
	if q := r.URL.Query().Get("token"); q != "" {
		return q
	}
	return ""
}
