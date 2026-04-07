import { redirect } from "next/navigation";
import { getStatsRedirectUrl } from "@f3-region/redirects";

export const dynamic = "force-dynamic";

export default function StatsRedirect() {
  redirect(getStatsRedirectUrl());
}
