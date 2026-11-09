import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const config = [
  ...nextVitals,
  ...nextTs,
  {
    // Static export: next/image cannot optimize anything, so plain <img>/<picture> with explicit
    // width/height (and pre-compressed AVIF/WebP files) is the lighter choice. The pages ship no
    // JavaScript (scripts/postbuild.mjs), so plain <a> links are what the visitor gets anyway.
    rules: { "@next/next/no-img-element": "off", "@next/next/no-html-link-for-pages": "off" },
  },
  { ignores: [".next/**", "out/**", "node_modules/**", "next-env.d.ts"] },
];

export default config;
