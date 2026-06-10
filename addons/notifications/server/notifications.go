package notifications

import server "github.com/aceso/server"

func init() {
	server.RegisterAddon(&notificationsAddon{})
}

type notificationsAddon struct{}

func (a *notificationsAddon) Register() error {
	// register webhook handler: POST /api/webhooks/notifications
	return nil
}
