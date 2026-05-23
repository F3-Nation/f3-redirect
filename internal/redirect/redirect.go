// Package redirect provides the HTTP handler that turns an incoming request
// into a 301/302 to the configured target for its Host.
package redirect

import (
	"net/http"

	"github.com/F3-Nation/f3-redirect/internal/mappings"
)

// Resolver returns the target URL for a request host.
type Resolver interface {
	Resolve(host string) (string, bool)
}

// Handler redirects each request to the target configured for its Host header.
// Unknown hosts get 404. The redirect status is Status (301 or 302).
type Handler struct {
	Resolver Resolver
	Status   int
}

// NewHandler builds a redirect handler. status must be 301 or 302; any other
// value falls back to 302 (safer default while DNS/cert setup settles).
func NewHandler(r Resolver, status int) *Handler {
	if status != http.StatusMovedPermanently && status != http.StatusFound {
		status = http.StatusFound
	}
	return &Handler{Resolver: r, Status: status}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// A bare health check (no Host match needed) for load balancers / probes.
	if r.URL.Path == "/healthz" {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
		return
	}

	host := mappings.NormalizeHost(r.Host)
	target, ok := h.Resolver.Resolve(host)
	if !ok {
		http.Error(w, "no redirect configured for this host", http.StatusNotFound)
		return
	}
	http.Redirect(w, r, target, h.Status)
}
