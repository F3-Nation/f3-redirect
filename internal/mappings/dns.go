package mappings

import "fmt"

// DNSRecord is a single DNS record a tenant must create to activate a redirect.
type DNSRecord struct {
	Type  string // "A" or "CNAME"
	Name  string // the record name (the host itself)
	Value string // the value: a static IP (A) or our canonical hostname (CNAME)
	Note  string // human-friendly explanation
}

// DNSOptions describe our serving endpoint so we can tell tenants what to point
// their domains at.
type DNSOptions struct {
	// StaticIP is the reserved public IP of the redirect tier. Apex domains
	// point an A record here.
	StaticIP string
	// CanonicalHost, when set, is the hostname subdomains should CNAME to. When
	// empty, subdomains are told to CNAME to their own apex (which must itself
	// carry an A record to StaticIP).
	CanonicalHost string
}

// DNSInstructions returns the DNS record(s) required to activate the mapping.
//
//   - An apex/root domain cannot CNAME, so it gets an A record to StaticIP.
//   - A subdomain gets a CNAME to CanonicalHost (or, if unset, to its own apex).
func DNSInstructions(m Mapping, opt DNSOptions) []DNSRecord {
	host := NormalizeHost(m.Host)

	if IsApex(host) {
		return []DNSRecord{{
			Type:  "A",
			Name:  host,
			Value: opt.StaticIP,
			Note:  fmt.Sprintf("%s is an apex domain and cannot use a CNAME; point an A record at the redirect tier's static IP.", host),
		}}
	}

	target := opt.CanonicalHost
	note := fmt.Sprintf("%s is a subdomain; CNAME it to our canonical redirect host.", host)
	if target == "" {
		target = ApexOf(host)
		note = fmt.Sprintf("%s is a subdomain; CNAME it to %s (which must carry an A record to %s).", host, target, opt.StaticIP)
	}
	return []DNSRecord{{
		Type:  "CNAME",
		Name:  host,
		Value: target,
		Note:  note,
	}}
}
