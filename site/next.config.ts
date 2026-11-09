import type { NextConfig } from "next";

// Static export: every page is plain HTML generated at build time. Vercel serves the `out/` folder
// from its CDN; scripts/postbuild.mjs then strips the client JavaScript the pages do not need.
const nextConfig: NextConfig = {
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
  poweredByHeader: false,
  reactStrictMode: true,
  experimental: {
    globalNotFound: true,
    inlineCss: true,
  },
};

export default nextConfig;
