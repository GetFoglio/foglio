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
- Hosting on the custom domain: set the repository variable `CUSTOM_DOMAIN` (e.g. `getfoglio.app`) and
  the custom domain in *Settings ▸ Pages*; without it the site is built for `https://<owner>.github.io/foglio/`.
