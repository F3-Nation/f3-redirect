import path from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: { "@": path.resolve(__dirname, "src") },
  },
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
    env: {
      // Integration tests run against the local dockerized Postgres and write
      // the export to a temp file (never GCS).
      DATABASE_URL: process.env.TEST_DATABASE_URL ?? "postgres://postgres:devpass@localhost:5433/f3redirect",
      EXPORT_LOCAL_PATH: "/tmp/vitest-redirects.json",
      CONFIG_BUCKET: "test-bucket",
      REDIRECT_STATIC_IP: "34.172.36.60",
      BETTER_AUTH_SECRET: "test-secret-test-secret-test-secret",
    },
    coverage: {
      provider: "v8",
      include: ["src/lib/**", "src/app/api/**"],
      reportsDirectory: "./coverage",
      thresholds: { lines: 70, functions: 70, statements: 70, branches: 60 },
    },
  },
});
