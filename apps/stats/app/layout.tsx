import type { Metadata } from "next";

const regionName = process.env.REGION_NAME ?? "F3 Region";

export const metadata: Metadata = {
  title: `F3 ${regionName} Metrics | YTD Totals`,
  description: `Track F3 ${regionName} year-to-date workout totals, attendance metrics, and stats.`,
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
