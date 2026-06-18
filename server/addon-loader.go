package server

// Addon is implemented by every server-side addon.
type Addon interface {
	// Register wires the addon into the provided mux and shared services.
	Register(deps *ServerDeps) error
}

var registry []Addon

// RegisterAddon is called by each addon's init() to enroll itself.
func RegisterAddon(a Addon) {
	registry = append(registry, a)
}

// LoadAll initialises every registered addon in registration order.
func LoadAll(deps *ServerDeps) {
	for _, a := range registry {
		if err := a.Register(deps); err != nil {
			panic("addon registration failed: " + err.Error())
		}
	}
}
