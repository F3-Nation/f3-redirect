import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "F3 Redirect — custom domain redirects",
  description: "Register a custom domain and redirect it anywhere.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <main className="container">{children}</main>
      </body>
    </html>
  );
}
