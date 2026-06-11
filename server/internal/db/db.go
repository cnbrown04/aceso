package db

// WhoopHRSample is one heart-rate reading from the strap.
type WhoopHRSample struct {
	DeviceID string
	TS       int64
	BPM      int
}

// WhoopRRInterval is one R-R interval reading.
type WhoopRRInterval struct {
	DeviceID string
	TS       int64
	RRMS     int
}

// WhoopBatterySample is one battery-level reading.
type WhoopBatterySample struct {
	DeviceID string
	TS       int64
	Pct      float64
}

// WhoopStore persists WHOOP samples.
type WhoopStore interface {
	SaveHRSamples(samples []WhoopHRSample) error
	SaveRRIntervals(intervals []WhoopRRInterval) error
	SaveBatterySamples(samples []WhoopBatterySample) error
}

// memoryStore is a no-op store for development. Replace with a real DB implementation.
type memoryStore struct{}

// NewMemoryStore returns a WhoopStore that discards all data.
// Swap this out for a real SQLite or Postgres store when the DB layer is ready.
func NewMemoryStore() WhoopStore { return &memoryStore{} }

func (s *memoryStore) SaveHRSamples(_ []WhoopHRSample) error        { return nil }
func (s *memoryStore) SaveRRIntervals(_ []WhoopRRInterval) error     { return nil }
func (s *memoryStore) SaveBatterySamples(_ []WhoopBatterySample) error { return nil }
