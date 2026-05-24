import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error("DATABASE_URL is not set");
}

// Cloud SQL via the Cloud Run connector uses a unix-socket form
//   postgres://user:pass@/db?host=/cloudsql/PROJECT:REGION:INSTANCE
// whose empty host is rejected by the WHATWG URL parser, so build the client
// from explicit options in that case. Standard TCP URLs (Neon, local Postgres)
// pass straight through.
function makeClient() {
  const socket = connectionString!.match(
    /^postgres(?:ql)?:\/\/([^:@/]+):([^@/]+)@\/([^?]+)\?host=(.+)$/,
  );
  if (socket) {
    const [, user, pass, database, host] = socket;
    return postgres({
      host: decodeURIComponent(host),
      database: decodeURIComponent(database),
      username: decodeURIComponent(user),
      password: decodeURIComponent(pass),
      prepare: false,
    });
  }
  return postgres(connectionString!, { prepare: false });
}

const client = makeClient();

export const db = drizzle(client, { schema });
export { schema };
