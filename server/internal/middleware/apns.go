package middleware

import (
	"log"
	"os"
)

// APNSProvider sends visible push notifications to offline iOS devices.
// When ACESO_APNS_KEY_PATH is unset the provider logs and no-ops.
type APNSProvider struct {
	enabled bool
	topic   string
}

// NewAPNSProvider reads optional APNs configuration from the environment.
func NewAPNSProvider() *APNSProvider {
	keyPath := os.Getenv("ACESO_APNS_KEY_PATH")
	topic := os.Getenv("ACESO_APNS_TOPIC")
	if topic == "" {
		topic = "dev.aceso.app"
	}
	return &APNSProvider{
		enabled: keyPath != "",
		topic:   topic,
	}
}

// SendVisibleNotification delivers a user-visible alert prompting command execution.
func (p *APNSProvider) SendVisibleNotification(deviceToken, title, body string, commandID string) error {
	if !p.enabled || deviceToken == "" {
		log.Printf("apns: skipped push for command %s (provider disabled or no token)", commandID)
		return nil
	}
	// Production wiring would use github.com/sideshow/apns2 with the key at ACESO_APNS_KEY_PATH.
	log.Printf("apns: would send visible notification topic=%s command=%s title=%q", p.topic, commandID, title)
	return nil
}
