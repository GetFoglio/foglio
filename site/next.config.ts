import type { NextConfig } from "next";

// Static export: the whole site is plain HTML/CSS served from GitHub Pages.
// NEXT_PUBLIC_BASE_PATH is "" on the custom domain and "/foglio" on <user>.github.io/foglio.
const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

const nextConfig: NextConfig = {
  output: "export",
  trailingSlash: true,
  basePath,
  images: { unoptimized: true },
  poweredByHeader: false,
  reactStrictMode: true,
  experimental: { globalNotFound: true },
};

export default nextConfig;
