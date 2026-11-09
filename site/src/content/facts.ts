/**
 * Measured, verifiable facts about Foglio. Single source of truth for numbers shown on the site.
 * Measured on a MacBook Air M4 (16 GB), macOS 27, Foglio 1.0, November 2026.
 * Memory = `footprint` of the running process; times = median of several runs.
 */

export const site = {
  name: "Foglio",
  domain: "getfoglio.app",
  url: "https://getfoglio.app",
  repo: "https://github.com/Acid236/foglio",
  version: "1.0",
  released: "2026-11-09",
  minMacOS: "14",
  license: "MIT / Apache-2.0",
} as const;

export const downloadUrl = `${site.repo}/releases/download/v${site.version}/Foglio-${site.version}.dmg`;
export const releasesUrl = `${site.repo}/releases`;

export const facts = {
  dmgMB: 7.5, // universal DMG (Apple silicon + Intel)
  appMB: 19, // installed .app, universal
  launchSeconds: 0.24, // launch to first frame, warm
  idleMemoryMB: 58, // empty workbook
  idleCPU: 0, // % CPU while idle
  open100kSeconds: 1.1, // open a 100,000-row xlsx with 300,000 formulas
  open100kMemoryMB: 171,
  editMs: 16, // one edit + incremental recalculation on that 100k-row workbook
  fullRecalcMs: 64, // full recalculation of the 100k-row workbook (300k formulas)
  save100kSeconds: 0.46,
  vlookupBeforeMs: 1703, // 1,000 VLOOKUPs over 10k rows, upstream IronCalc 0.9.1
  vlookupAfterMs: 1.3, // same, Foglio's engine fork (indexed lookups)
  functions: 500, // ~500 Excel functions
  functionsTested: 195,
  functionsOk: 191,
  uiTests: 69,
  price: 0,
} as const;

/**
 * Download size of each app as listed by its official source, checked November 2026
 * (see comparisonSources): Foglio DMG; Numbers and Excel on the Mac App Store; LibreOffice DMG
 * from libreoffice.org. Used only for the size bar chart.
 */
export const sizeComparisonMB = {
  foglio: 7.5,
  libreoffice: 299,
  numbers: 661,
  excel: 1200,
} as const;
