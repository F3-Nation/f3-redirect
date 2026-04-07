import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  transpilePackages: ["@f3-region/redirects"],
};

export default nextConfig;
