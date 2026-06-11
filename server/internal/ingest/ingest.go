package ingest

import (
	"encoding/json"
	"net/http"

	"github.com/aceso/server/internal/db"
)

// Handler handles WHOOP data ingest requests.
type Handler struct {
	store db.WhoopStore
}

// New creates an ingest Handler backed by the given store.
func New(store db.WhoopStore) *Handler {
	return &Handler{store: store}
}

// Register mounts the ingest routes onto mux.
func (h *Handler) Register(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/whoop/ingest", h.handleIngest)
}

// ingestRequest mirrors WhoopSampleBatch from the iOS client.
type ingestRequest struct {
	DeviceID string `json:"device_id"`
	HRSamples []struct {
		TS  int64 `json:"ts"`
		BPM int   `json:"bpm"`
	} `json:"hr_samples"`
	RRIntervals []struct {
		TS   int64 `json:"ts"`
		RRMS int   `json:"rr_ms"`
	} `json:"rr_intervals"`
	BatterySamples []struct {
		TS  int64   `json:"ts"`
		Pct float64 `json:"pct"`
	} `json:"battery_samples"`
}

func (h *Handler) handleIngest(w http.ResponseWriter, r *http.Request) {
	var req ingestRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	if req.DeviceID == "" {
		http.Error(w, "missing device_id", http.StatusBadRequest)
		return
	}

	if len(req.HRSamples) > 0 {
		samples := make([]db.WhoopHRSample, len(req.HRSamples))
		for i, s := range req.HRSamples {
			samples[i] = db.WhoopHRSample{DeviceID: req.DeviceID, TS: s.TS, BPM: s.BPM}
		}
		if err := h.store.SaveHRSamples(samples); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
	}

	if len(req.RRIntervals) > 0 {
		intervals := make([]db.WhoopRRInterval, len(req.RRIntervals))
		for i, v := range req.RRIntervals {
			intervals[i] = db.WhoopRRInterval{DeviceID: req.DeviceID, TS: v.TS, RRMS: v.RRMS}
		}
		if err := h.store.SaveRRIntervals(intervals); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
	}

	if len(req.BatterySamples) > 0 {
		samples := make([]db.WhoopBatterySample, len(req.BatterySamples))
		for i, s := range req.BatterySamples {
			samples[i] = db.WhoopBatterySample{DeviceID: req.DeviceID, TS: s.TS, Pct: s.Pct}
		}
		if err := h.store.SaveBatterySamples(samples); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
	}

	w.WriteHeader(http.StatusNoContent)
}
