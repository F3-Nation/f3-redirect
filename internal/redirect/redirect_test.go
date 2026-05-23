package redirect

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/F3-Nation/f3-redirect/internal/mappings"
)

func liveFrom(t *testing.T, c mappings.Config) *Live {
	t.Helper()
	dir := t.TempDir()
	store := mappings.NewFileStore(dir + "/c.json")
	if err := store.Save(context.Background(), c); err != nil {
		t.Fatal(err)
	}
	l, err := NewLive(context.Background(), store)
	if err != nil {
		t.Fatal(err)
	}
	return l
}

func cfg() mappings.Config {
	return mappings.Config{Mappings: []mappings.Mapping{
		{Host: "f3muletown.com", Target: "https://regions.f3nation.com/muletown"},
		{Host: "stats.f3muletown.com", Target: "https://pax-vault.f3nation.com/stats/region/35838"},
	}}
}

func TestHandlerRedirects(t *testing.T) {
	h := NewHandler(liveFrom(t, cfg()), http.StatusFound)

	req := httptest.NewRequest(http.MethodGet, "http://f3muletown.com/anything?q=1", nil)
	req.Host = "f3muletown.com"
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusFound {
		t.Fatalf("status = %d want 302", rec.Code)
	}
	if loc := rec.Header().Get("Location"); loc != "https://regions.f3nation.com/muletown" {
		t.Errorf("Location = %q", loc)
	}
}

func TestHandlerUnknownHost404(t *testing.T) {
	h := NewHandler(liveFrom(t, cfg()), http.StatusMovedPermanently)
	req := httptest.NewRequest(http.MethodGet, "http://nope.example.com/", nil)
	req.Host = "nope.example.com"
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Errorf("unknown host status = %d want 404", rec.Code)
	}
}

func TestHandlerHealthz(t *testing.T) {
	h := NewHandler(liveFrom(t, cfg()), http.StatusFound)
	req := httptest.NewRequest(http.MethodGet, "http://anything/healthz", nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK || rec.Body.String() != "ok" {
		t.Errorf("healthz = %d %q", rec.Code, rec.Body.String())
	}
}

func TestNewHandlerStatusFallback(t *testing.T) {
	if h := NewHandler(nil, 307); h.Status != http.StatusFound {
		t.Errorf("invalid status should fall back to 302, got %d", h.Status)
	}
	if h := NewHandler(nil, http.StatusMovedPermanently); h.Status != http.StatusMovedPermanently {
		t.Errorf("301 should be honored, got %d", h.Status)
	}
}

func TestLiveConfigAndWatch(t *testing.T) {
	dir := t.TempDir()
	store := mappings.NewFileStore(dir + "/c.json")
	if err := store.Save(context.Background(), cfg()); err != nil {
		t.Fatal(err)
	}
	l, err := NewLive(context.Background(), store)
	if err != nil {
		t.Fatal(err)
	}
	if len(l.Config().Mappings) != 2 {
		t.Errorf("Config() snapshot len = %d want 2", len(l.Config().Mappings))
	}

	// Watch should reload at least once, then exit promptly on cancel.
	updated := cfg().Upsert("watched.f3muletown.com", "https://example.com/w")
	if err := store.Save(context.Background(), updated); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { l.Watch(ctx, time.Millisecond, nil); close(done) }()
	deadline := time.After(2 * time.Second)
	for !l.IsRegistered("watched.f3muletown.com") {
		select {
		case <-deadline:
			cancel()
			t.Fatal("Watch did not reload within deadline")
		case <-time.After(2 * time.Millisecond):
		}
	}
	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Watch did not return after cancel")
	}
}

func TestLiveReload(t *testing.T) {
	dir := t.TempDir()
	store := mappings.NewFileStore(dir + "/c.json")
	if err := store.Save(context.Background(), cfg()); err != nil {
		t.Fatal(err)
	}
	l, err := NewLive(context.Background(), store)
	if err != nil {
		t.Fatal(err)
	}
	if l.IsRegistered("new.f3muletown.com") {
		t.Fatal("should not be registered yet")
	}
	updated := cfg().Upsert("new.f3muletown.com", "https://example.com/new")
	if err := store.Save(context.Background(), updated); err != nil {
		t.Fatal(err)
	}
	if err := l.Reload(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !l.IsRegistered("new.f3muletown.com") {
		t.Error("reload should pick up the new mapping")
	}
}
