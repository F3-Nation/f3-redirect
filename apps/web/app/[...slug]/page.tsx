import { redirect } from "next/navigation";
import { getRegionRedirectUrl } from "@f3-region/redirects";

export const dynamic = "force-dynamic";

export default function CatchAll() {
  redirect(getRegionRedirectUrl());
}
