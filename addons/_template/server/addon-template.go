package templateaddon

import server "github.com/aceso/server"

func init() {
	server.RegisterAddon(&templateAddon{})
}

type templateAddon struct{}

func (a *templateAddon) Register() error {
	// wire up routes, services, etc.
	return nil
}
