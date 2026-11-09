# getfoglio.app

The website of [Foglio](../README.md): Next.js (App Router) + TypeScript, exported as static HTML
(`output: "export"`) and deployed to GitHub Pages by [`.github/workflows/site.yml`](../.github/workflows/site.yml).

```sh
npm ci
npm run dev          # http://localhost:3000
npm run lint && npm run typecheck
npm run build        # → out/
```

- English lives at `/`, Italian at `/it/` (two root layouts: `src/app/(en)` and `src/app/(it)/it`).
- All text is in `src/content/` (`copy.en.ts`, `copy.it.ts`, `comparison.ts`, `alternatives.ts`,
  `guides.ts`); measured numbers come only from `src/content/facts.ts`. `SEO.md` has the keyword notes.
- No client-side JavaScript of our own, no web fonts, no trackers. Screenshots are real renders of the
  app (`public/screenshots/`).
- Deploy: GitHub Pages serves the `gh-pages` branch. `scripts/deploy_site.sh` builds and publishes it
  from your Mac; the workflow does the same on every push to `main` that touches `site/`.
- Custom domain: `CUSTOM_DOMAIN=getfoglio.app scripts/deploy_site.sh` (and the repository variable
  `CUSTOM_DOMAIN` for the workflow), then set the domain in *Settings ▸ Pages*. Without it the site is
  built for `https://<owner>.github.io/foglio/`.
