// Runs after `next build` (static export). The pages have no interactive parts (menus and FAQs are
// native <details>), so the React runtime and the RSC payload are dead weight: this removes every
// <script> except JSON-LD, the script preloads, and the files only those scripts used.
// Result: plain HTML with inline CSS, zero JavaScript.
import { readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const out = fileURLToPath(new URL("../out/", import.meta.url));

function walk(dir, files = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, files);
    else files.push(p);
  }
  return files;
}

let before = 0;
let after = 0;
let pages = 0;
for (const file of walk(out)) {
  if (file.endsWith(".txt") && !file.endsWith("robots.txt")) {
    rmSync(file); // RSC payloads for client-side navigation
    continue;
  }
  if (!file.endsWith(".html")) continue;
  const html = readFileSync(file, "utf8");
  const stripped = html
    .replace(/<script\b(?![^>]*application\/ld\+json)[^>]*>[\s\S]*?<\/script>/g, "")
    .replace(/<link\b[^>]*\bas="script"[^>]*\/?>/g, "")
    .replace(/<link\b[^>]*rel="modulepreload"[^>]*\/?>/g, "");
  if (/<script\b(?![^>]*application\/ld\+json)/.test(stripped)) throw new Error(`script left in ${file}`);
  before += html.length;
  after += stripped.length;
  pages++;
  writeFileSync(file, stripped);
}

// Nothing references the JavaScript chunks any more.
const chunks = join(out, "_next/static/chunks");
for (const f of walk(chunks)) if (f.endsWith(".js")) rmSync(f);

const left = walk(out)
  .filter((f) => f.endsWith(".html"))
  .some((f) => readFileSync(f, "utf8").includes("/_next/static/chunks/") && /\.js["']/.test(readFileSync(f, "utf8")));
if (left) throw new Error("a page still references a JavaScript chunk");

console.log(`postbuild: ${pages} pages, HTML ${(before / 1024).toFixed(0)} KB → ${(after / 1024).toFixed(0)} KB, no JavaScript`);
