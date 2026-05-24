import { writeFile } from "node:fs/promises";
import { Storage } from "@google-cloud/storage";
import { db } from "@/db";
import { domain } from "@/db/schema";

const BUCKET = process.env.CONFIG_BUCKET ?? "f3-redirects-redirect";
const OBJECT = process.env.CONFIG_OBJECT ?? "config/redirects.json";
// Dev-only: when set, write the config to a local file instead of GCS (lets
// local development exercise the full export path without GCS credentials).
const LOCAL_PATH = process.env.EXPORT_LOCAL_PATH;

/**
 * Regenerate the flat-file config the Go redirect tier reads, from the current
 * set of registered domains in Postgres (the source of truth). Called after
 * any add/remove so the live service and the on-demand-TLS gate stay in sync.
 *
 * Auth is via Application Default Credentials — the Cloud Run runtime service
 * account (granted storage.objectAdmin on the bucket). No keys.
 */
export async function exportConfigToGCS(): Promise<number> {
  const rows = await db
    .select({ host: domain.hostname, target: domain.destinationUrl })
    .from(domain);

  const mappings = rows
    .map((r) => ({ host: r.host, target: r.target }))
    .sort((a, b) => a.host.localeCompare(b.host));

  const body = JSON.stringify({ mappings }, null, 2) + "\n";

  if (LOCAL_PATH) {
    await writeFile(LOCAL_PATH, body, "utf8");
    return mappings.length;
  }

  const storage = new Storage();
  await storage.bucket(BUCKET).file(OBJECT).save(body, {
    contentType: "application/json",
    resumable: false,
  });

  return mappings.length;
}
