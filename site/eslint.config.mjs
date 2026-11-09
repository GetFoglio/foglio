import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const config = [
  ...nextVitals,
  ...nextTs,
  {
    // Static export: next/image cannot optimize anything, so plain <img>/<picture> with explicit
    // width/height (and pre-compressed WebP files) is the lighter choice.
    rules: { "@next/next/no-img-element": "off" },
  },
  { ignores: [".next/**", "out/**", "node_modules/**", "next-env.d.ts"] },
];

export default config;
