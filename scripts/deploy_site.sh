#!/bin/bash
# Builds the website (site/) and publishes it to the gh-pages branch, which GitHub Pages serves.
#   scripts/deploy_site.sh              → https://<owner>.github.io/foglio/
#   CUSTOM_DOMAIN=getfoglio.app scripts/deploy_site.sh   → served at the root of the custom domain
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REMOTE=${REMOTE:-$(git -C "$ROOT" remote get-url origin)}
cd "$ROOT/site"
if [[ -n "${CUSTOM_DOMAIN:-}" ]]; then export NEXT_PUBLIC_BASE_PATH=""; else export NEXT_PUBLIC_BASE_PATH="/foglio"; fi
[[ -d node_modules ]] || npm ci
npm run lint
npm run typecheck
npm run build
touch out/.nojekyll
if [[ -n "${CUSTOM_DOMAIN:-}" ]]; then echo "$CUSTOM_DOMAIN" > out/CNAME; fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp -R out/. "$TMP"
cd "$TMP"
git init -q -b gh-pages
git config user.name "$(git -C "$ROOT" config user.name)"
git config user.email "$(git -C "$ROOT" config user.email)"
git add -A
git commit -qm "Website build from $(git -C "$ROOT" rev-parse --short HEAD)"
git push -q -f "$REMOTE" gh-pages
echo "Published to gh-pages"
