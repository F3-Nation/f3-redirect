import { headers } from "next/headers";
import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { auth } from "@/auth";
import { db } from "@/db";
import { domain } from "@/db/schema";
import { exportConfigToGCS } from "@/lib/gcs-export";

// DELETE /api/domains/:id — remove one of the signed-in user's domains.
export async function DELETE(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const sess = await auth.api.getSession({ headers: await headers() });
  const userId = sess?.user?.id;
  if (!userId) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const { id } = await params;
  const deleted = await db
    .delete(domain)
    .where(and(eq(domain.id, id), eq(domain.userId, userId)))
    .returning();

  if (deleted.length === 0) {
    return NextResponse.json({ error: "not found" }, { status: 404 });
  }

  await exportConfigToGCS();
  return NextResponse.json({ ok: true });
}
