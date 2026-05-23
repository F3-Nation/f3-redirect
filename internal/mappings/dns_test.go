package mappings

import "testing"

func TestDNSInstructionsApex(t *testing.T) {
	recs := DNSInstructions(
		Mapping{Host: "f3muletown.com", Target: "https://regions.f3nation.com/muletown"},
		DNSOptions{StaticIP: "203.0.113.10"},
	)
	if len(recs) != 1 {
		t.Fatalf("apex should yield 1 record, got %d", len(recs))
	}
	r := recs[0]
	if r.Type != "A" || r.Name != "f3muletown.com" || r.Value != "203.0.113.10" {
		t.Errorf("apex record = %+v", r)
	}
}

func TestDNSInstructionsSubdomainCanonical(t *testing.T) {
	recs := DNSInstructions(
		Mapping{Host: "stats.f3muletown.com", Target: "https://x"},
		DNSOptions{StaticIP: "203.0.113.10", CanonicalHost: "redirect.f3nation.com"},
	)
	if len(recs) != 1 || recs[0].Type != "CNAME" {
		t.Fatalf("subdomain should yield 1 CNAME, got %+v", recs)
	}
	if recs[0].Value != "redirect.f3nation.com" {
		t.Errorf("CNAME value = %q, want canonical host", recs[0].Value)
	}
}

func TestDNSInstructionsSubdomainFallsBackToApex(t *testing.T) {
	recs := DNSInstructions(
		Mapping{Host: "www.f3marshall.com", Target: "https://x"},
		DNSOptions{StaticIP: "203.0.113.10"}, // no canonical host
	)
	if recs[0].Type != "CNAME" || recs[0].Value != "f3marshall.com" {
		t.Errorf("subdomain fallback = %+v, want CNAME to apex", recs[0])
	}
}
