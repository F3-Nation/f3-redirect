"use client";

import { useRouter } from "next/navigation";
import { useRef, useState } from "react";
import { passkey, signOut } from "@/lib/auth-client";

function PasskeySetup() {
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  return (
    <div style={{ marginTop: "0.6rem" }}>
      <button
        disabled={busy}
        onClick={async () => {
          setBusy(true);
          setMsg(null);
          try {
            const res = await passkey.addPasskey();
            setMsg(res?.error ? `Could not add passkey: ${res.error.message}` : "Passkey added — you can use it to sign in next time.");
          } catch (e) {
            setMsg(e instanceof Error ? e.message : "Could not add passkey");
          } finally {
            setBusy(false);
          }
        }}
      >
        {busy ? "Follow your device prompt…" : "Add a passkey"}
      </button>
      <span className="muted" style={{ marginLeft: "0.6rem" }}>
        Optional — sign in faster next time with Touch ID / Face ID / a security key.
      </span>
      {msg && <p className="muted" style={{ marginTop: "0.4rem" }}>{msg}</p>}
    </div>
  );
}

type DnsRecord = { type: string; name: string; value: string; note: string; optional?: boolean };
type DomainItem = { id: string; hostname: string; destination: string; dns: DnsRecord[] };

// Stacked, full-width record blocks — no horizontal scroll on mobile.
function DnsRecords({ dns }: { dns: DnsRecord[] }) {
  const sorted = [...dns].sort((a, b) => Number(a.optional) - Number(b.optional));
  return (
    <div>
      {sorted.map((r, i) => (
        <div className="dns-record" key={i}>
          <div className="dns-record-head">
            <span className="badge">{r.type}</span>
            {r.optional ? (
              <span className="muted">recommended</span>
            ) : (
              <strong className="req">required</strong>
            )}
          </div>
          <dl className="dns-kv">
            <dt>Name</dt>
            <dd className="mono">{r.name}</dd>
            <dt>Value</dt>
            <dd className="mono">{r.value}</dd>
          </dl>
          <p className="muted dns-note">{r.note}</p>
        </div>
      ))}
    </div>
  );
}

// Bottom-sheet drawer (native <dialog>) — mobile-friendly, no horizontal scroll.
function DnsSheet({ domain }: { domain: DomainItem }) {
  const ref = useRef<HTMLDialogElement>(null);
  return (
    <>
      <button onClick={() => ref.current?.showModal()}>View DNS records</button>
      <dialog ref={ref} className="sheet" onClick={(e) => e.target === ref.current && ref.current?.close()}>
        <div className="sheet-body">
          <div className="row">
            <strong className="mono">{domain.hostname}</strong>
            <button onClick={() => ref.current?.close()}>Close</button>
          </div>
          <p className="muted" style={{ margin: "0.3rem 0 0.8rem" }}>
            Add these DNS records at your registrar to activate the redirect:
          </p>
          <DnsRecords dns={domain.dns} />
        </div>
      </dialog>
    </>
  );
}

export function Dashboard({
  initial,
  userEmail,
}: {
  initial: DomainItem[];
  userEmail: string;
}) {
  const router = useRouter();
  const [domains, setDomains] = useState<DomainItem[]>(initial);
  const [hostname, setHostname] = useState("");
  const [destination, setDestination] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function add(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      const res = await fetch("/api/domains", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ hostname, destination }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error ?? "failed to register domain");
        return;
      }
      setDomains((d) => [...d, data.domain].sort((a, b) => a.hostname.localeCompare(b.hostname)));
      setHostname("");
      setDestination("");
    } finally {
      setBusy(false);
    }
  }

  async function remove(id: string) {
    setBusy(true);
    try {
      const res = await fetch(`/api/domains/${id}`, { method: "DELETE" });
      if (res.ok) setDomains((d) => d.filter((x) => x.id !== id));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <div className="row">
        <h1>Your domains</h1>
        <span className="muted">
          {userEmail} ·{" "}
          <a
            style={{ cursor: "pointer" }}
            onClick={async () => {
              await signOut();
              router.push("/");
              router.refresh();
            }}
          >
            sign out
          </a>
        </span>
      </div>

      <div className="card">
        <strong>Security</strong>
        <PasskeySetup />
      </div>

      <div className="card">
        <form onSubmit={add}>
          <label htmlFor="hostname">Custom domain</label>
          <input
            id="hostname"
            placeholder="f3muletown.com"
            value={hostname}
            onChange={(e) => setHostname(e.target.value)}
            autoCapitalize="off"
            autoCorrect="off"
          />
          <label htmlFor="destination">Redirect destination</label>
          <input
            id="destination"
            placeholder="https://regions.f3nation.com/muletown"
            value={destination}
            onChange={(e) => setDestination(e.target.value)}
            autoCapitalize="off"
            autoCorrect="off"
          />
          <div style={{ marginTop: "0.9rem" }}>
            <button className="primary" disabled={busy} type="submit">
              {busy ? "Working…" : "Register domain"}
            </button>
          </div>
          {error && <p className="error">{error}</p>}
        </form>
      </div>

      {domains.length === 0 && <p className="muted">No domains yet — register one above.</p>}

      {domains.map((d) => (
        <div className="card" key={d.id}>
          <div className="row">
            <div>
              <strong className="mono">{d.hostname}</strong>
              <div className="muted mono">→ {d.destination}</div>
            </div>
            <button className="danger" disabled={busy} onClick={() => remove(d.id)}>
              Remove
            </button>
          </div>
          <div style={{ marginTop: "0.6rem" }}>
            <DnsSheet domain={d} />
          </div>
        </div>
      ))}
    </div>
  );
}
