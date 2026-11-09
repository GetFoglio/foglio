# Foglio website: SEO notes

Last updated 2026-11-09. Content lives in `src/content/` (`copy.en.ts`, `copy.it.ts`, `comparison.ts`,
`alternatives.ts`, `guides.ts`). This file holds the research and reasoning behind it.

## How the keyword research was done (and its limits)

I had no access to a keyword tool with real search volumes (Ahrefs, Semrush, Google Keyword
Planner). The signals below come from:

- **SERP inspection** (web search, November 2026): who ranks, how many pages target the term, and
  whether results are listicles, vendor pages, forum threads or Apple/Microsoft help pages.
- **Question patterns** in Apple Community threads and Italian how-to sites (Aranzulla, Navigaweb,
  iPhoneItalia), which show how people phrase the problem.
- **Experience** with how these queries usually behave. "Volume" below is a relative estimate
  (High / Medium / Low), not a measured number. **Check it in Search Console after 4–8 weeks** and
  in Keyword Planner before investing in new pages.

General picture:

- "excel alternative mac" style queries are **high volume, very competitive**, dominated by
  listicles from SaaS vendors (ClickUp, WPS, Setapp, Softpicker, Spreadsheetpoint). A new domain
  will not rank for the head term quickly. The long tail ("free excel alternative for mac that opens
  xlsx", "lightweight", "native", "open source", "no subscription") is reachable.
- **How-to problems** ("open xlsx on mac without excel", "csv opens in one column mac",
  "numbers can't open xls") are medium volume, high intent, and answered mostly by thin vendor
  posts and old forum threads. **Best near-term opportunity**: we can answer them better and
  honestly.
- **Italian** SERPs are far less crowded. "alternativa gratuita a excel per mac", "aprire file
  xlsx su mac", "foglio di calcolo gratis mac" are covered mainly by Aranzulla, ONLYOFFICE's
  Italian blog and translated ClickUp pages. The brand name is itself an Italian word, which helps
  relevance but makes brand search ambiguous ("foglio" also means a sheet of paper / a sheet in
  Excel). Always pair the brand with "Mac" or "app" in copy.
- The **Italian↔English function names** page targets a steady, evergreen query family
  ("cerca.vert in inglese", "vlookup in italiano", "funzioni excel inglese italiano") with weak,
  ad-heavy results. Good link-bait for both languages.

## Target keyword per page

One primary keyword per page; secondaries are used naturally in headings and body.

| Page | EN primary | EN secondary | IT primary | IT secondary | Intent / volume (est.) |
|---|---|---|---|---|---|
| `/` | free spreadsheet app for Mac | excel compatible, open source spreadsheet mac, native | foglio di calcolo gratis per Mac | programma excel gratis mac, foglio elettronico mac | Commercial / High |
| `/compare/` | Excel vs Numbers vs LibreOffice vs Google Sheets | mac spreadsheet comparison, best spreadsheet app mac | confronto Excel Numbers LibreOffice Fogli Google | miglior foglio di calcolo per Mac | Commercial investigation / Medium |
| `/technology/` | native Mac spreadsheet Swift Rust | IronCalc, not Electron, AppKit | foglio di calcolo nativo Mac Swift Rust | — | Informational, dev audience / Low (links, HN/Reddit) |
| `/download/` | download Foglio for Mac | free spreadsheet download mac, unidentified developer | scaricare Foglio per Mac | foglio di calcolo gratis da scaricare, sviluppatore non identificato | Navigational / brand |
| `/alternatives/` | Excel, Numbers, Google Sheets alternatives Mac | — | alternative a Excel, Numbers, Fogli Google | — | Hub page |
| `/alternatives/excel-for-mac/` | free Excel alternative for Mac | excel without subscription mac, open xlsx free | alternativa gratuita a Excel per Mac | excel gratis mac, senza abbonamento microsoft 365 | Commercial / High (competitive) |
| `/alternatives/numbers/` | Numbers alternative (for Excel files) | numbers vs excel, numbers xlsx | alternativa a Numbers | numbers file excel, numbers non apre xlsx | Commercial / Low–Medium |
| `/alternatives/libreoffice/` | lightweight LibreOffice Calc alternative Mac | libreoffice mac slow / heavy | alternativa leggera a LibreOffice Calc | libreoffice mac pesante | Commercial / Low |
| `/alternatives/google-sheets/` | offline Google Sheets alternative | google sheets desktop app mac, private spreadsheet | alternativa offline a Fogli Google | fogli google offline mac | Commercial / Medium |
| `/guides/open-xlsx-on-mac-without-excel/` | open xlsx on Mac without Excel | how to open excel files on mac free | aprire file xlsx su Mac senza Excel | come aprire file excel su mac gratis | Informational, high intent / High |
| `/guides/open-xls-on-mac/` | open xls file on Mac | numbers unsupported version of excel, convert xls to xlsx mac | aprire file xls su Mac | convertire xls in xlsx mac | Informational / Medium |
| `/guides/open-csv-on-mac/` | open CSV file on Mac | csv one column mac, csv encoding mac, csv semicolon | aprire file CSV su Mac | csv una sola colonna, csv caratteri strani, csv punto e virgola | Informational / Medium–High |
| `/guides/free-spreadsheet-apps-for-mac/` | free spreadsheet apps for Mac | best free spreadsheet mac 2026 | fogli di calcolo gratis per Mac | programmi gratis fogli di calcolo mac | Commercial / High (competitive) |
| `/guides/excel-functions-italian-english/` | Excel function names in Italian | vlookup in italian, excel italian english translation | funzioni Excel in italiano e inglese | cerca.vert in inglese, somma.se in inglese | Informational / Medium, evergreen |

### Cannibalisation decisions

- The home page targets **"free spreadsheet app for Mac" / "foglio di calcolo gratis per Mac"**,
  and `/alternatives/excel-for-mac/` targets **"free Excel alternative for Mac" / "alternativa
  gratuita a Excel per Mac"**. Earlier drafts gave both the Excel keyword; I split them so they do not
  compete. The home page still mentions Excel heavily (it must), but its title leads with "spreadsheet".
- `/compare/` (table, all five apps) vs `/guides/free-spreadsheet-apps-for-mac/` (roundup, six
  free apps incl. Excel for the web and ONLYOFFICE): the comparison is the "vs" query, the roundup is
  the "best free … list" query. They link to each other.

## Titles and descriptions

Rules applied (and checked by script): title ≤ 60 characters including "| Foglio", description
120–155 characters, all unique across both locales, primary keyword at the start of the title,
brand at the end except on the home page where the brand leads (brand + category is the norm for
home pages and reads better in SERPs).

Rationale per pattern:

- **"How to …" titles** for guides match the query phrasing exactly ("How to Open xlsx Files on a
  Mac Without Excel"). Italian uses the infinitive/"Come …" forms people actually type ("Come aprire
  file xlsx su Mac senza Excel").
- **Descriptions lead with the user's problem** ("CSV opening in one column, with garbled accents…")
  and end with what the page delivers. No exclamation marks, no superlatives we cannot back.
- **Numbers in snippets** (7.5 MB, ~500 functions, 2026) improve CTR and are all from `facts.ts`.
- Year "(2026)" only on the roundup, the one page where freshness is part of the query. Remember to
  update it (title, description, `updated`) each year, or drop it.
- `ogTitle` set on the home page only, as a friendlier social share line.

## Internal linking plan

Every page links up to a hub and across to siblings. Implemented in the content:

- **Home** → `/compare/`, `/technology/`, `/download/`, all four alternatives, `/alternatives/`,
  guides for xlsx, xls, CSV, the function list (from the FAQ).
- **Compare** → roundup guide (FAQ); alternatives pages should be linked from the table's column
  headers by the design (suggestion: each competitor name links to its `/alternatives/<slug>/`).
- **Alternatives** → each links to `/compare/`, `/download/`, and to 1–3 sibling alternatives
  and relevant guides (Excel → roundup; Numbers → xlsx guide + function list; LibreOffice → xls
  guide + technology; Google Sheets → compare).
- **Guides** → each links to `/` (Foglio first mention), `/download/`, the matching alternatives
  page(s) and at least one other guide (xlsx ↔ CSV ↔ xls).
- **Index pages** `/alternatives/` ↔ `/guides/` link to each other in their intros.
- **Technology** → GitHub, IronCalc, calamine (external, authoritative) and `/download/`.

Suggestions for the components (not content):

- A "Related guides" block at the end of each article (2–3 cards from the same locale) would
  strengthen the mesh without stuffing links into the text.
- Breadcrumbs (Home ▸ Guides ▸ …) with `BreadcrumbList` JSON-LD.
- `hreflang` en / it / x-default on every page, since the slugs are identical in both locales.
- `SoftwareApplication` JSON-LD on home and download: `operatingSystem: "macOS 14+"`,
  `applicationCategory: "BusinessApplication"`, `offers.price: 0`, `license` URL, `downloadUrl`,
  `fileSize: "7.5MB"`. **Do not add `aggregateRating`**: there are no real ratings.
- `HowTo` JSON-LD is no longer shown as a rich result by Google; FAQPage JSON-LD (already planned)
  has limited visibility too but costs nothing.

## What the design should highlight

In order of persuasive weight, from what I learned writing the copy:

1. **Free with no catch**: price 0, no account, no ads, no telemetry, MIT/Apache. Put "no account"
   and "no subscription" next to the download button; that is the main objection for Excel users.
2. **It opens their `.xlsx` and saves it back as `.xlsx`**: the single feature most visitors need.
   A file-format strip (xlsx, xlsm, xls, xlsb, ods, csv, tsv in; xlsx, csv, pdf out) works well.
3. **Size bar chart** (7.5 MB vs hundreds of MB / GB): the most striking visual. See the data
   caveat below.
4. **Formulas in your language**: unusual and very concrete for Italian/German/Spanish/French
   visitors. Show a formula bar with `=SOMMA(A1:A10;B2)` on the Italian site and the same formula in
   English on the English site.
5. **Speed numbers**: 0.24 s launch, 16 ms recalculation on 300k formulas, and the 1,703 ms →
   1.3 ms VLOOKUP story (great for the technology page and for developer audiences).
6. **Honesty block**: a visible "What Foglio doesn't do yet" list (pivot tables, macros, password
   files, shapes, sparklines, collaboration, iOS). It builds trust and pre-empts bad reviews.
7. **Gatekeeper step**: screenshots of the Privacy & Security "Open Anyway" button (macOS 15+)
   and the right-click ▸ Open dialog (macOS 14). This is the biggest drop-off risk after download.
8. Smaller touches worth a screenshot: EMF/WMF clip art rendering, CSV auto-detection, dark mode,
   Insert Function browser, picture crop handles.

## Product claims to double-check before launch

- **Competitor sizes in `facts.ts` vs `comparison.ts` disagree.** `sizeComparisonMB` has Numbers
  260 MB, LibreOffice 595 MB, Excel 2,400 MB. What I found on 2026-11-09: Numbers App Store listing
  **661 MB** (a single universal listing for Mac/iPhone/iPad; the 260 MB figure matches older
  Mac-only listings), Excel Mac App Store **1.2 GB**, LibreOffice 26.8.2 Apple silicon DMG
  **≈ 299 MB** download (system requirements say up to 800 MB on disk; 595 MB may be a fair
  installed size but I could not verify it). The comparison table uses the figures I verified. The
  chart caption says "download or installed sizes", which covers the mix, but someone should
  align the two or label the chart bars precisely.
- **Numbers now requires macOS 26** (current version 15.4.2). Used in the copy as a point in
  Foglio's favour; re-check if Apple changes it.
- **Office Home 2024 price**: Microsoft's US page lists **$179.99**; many retailers still quote the
  older $149.99 MSRP. Italy: **149 €** on microsoft.com/it-it. Microsoft 365 Personal / Family:
  $99.99 / $129.99 per year (US), 99 € / 129 € (IT).
- **Apple Creator Studio**: $12.99/month or $129/year (US); 12,99 €/mese or 129 €/anno (IT), per
  Apple's announcement and Italian press. Numbers itself stays free.
- **"No network connections of its own"**: I grepped `app/Sources` and `core/` for networking code
  (URLSession, HTTP crates, Sparkle, analytics) and found none; the only outbound action is
  `NSWorkspace.open` when the user clicks a cell hyperlink. Keep this true (an update checker would
  change the copy in several places: home features, FAQ, download FAQ, Google Sheets page).
- **`.xls` / `.xlsb` / `.ods` import keeps values, formulas and dates but not cell formatting**
  (calamine path). The copy says so explicitly. If formatting import is added, update the xls guide,
  the LibreOffice page and two comparison cells.
- **Saving `.xlsm`**: Foglio's writable types are xlsx and csv, so macros are lost on save. Copy
  says "macros are not run and are not kept when you save". Verify the actual behaviour when saving
  an opened `.xlsm` (does it prompt Save As?).
- **LibreOffice has no LAMBDA**: based on the open bug tdf#138749; re-check against the 26.8
  release notes before launch.
- **Excel telemetry**: Microsoft's own page confirms required vs optional diagnostic data, not
  precisely what the Mac consumer app sends; the cell wording stays general.
- **Google Sheets + Gemini**: availability by plan changes often; the cell says "depending on plan".
- **Function names follow the Mac's language; separators and decimals follow the region**
  (`FormulaLocale.current` in `app/Sources/Engine.swift`). Function descriptions in autocomplete
  exist only in English and Italian (`FunctionDocs.swift`), so the copy promises "Italian
  descriptions" only on Italian pages.
- The README's Italian section is outdated ("circa 400 funzioni", "prime fasi di sviluppo"). Not
  used on the site, but worth updating because Google may surface the GitHub page for Italian queries.

## Ideas for future pages

High to low expected value:

1. **"Excel shortcuts on Mac" cheat sheet** (EN/IT): high-volume evergreen query; Foglio follows
   Excel for Mac conventions, so it doubles as product documentation.
2. **"Excel without subscription on Mac" / "Excel senza abbonamento"**: price-anxiety query
   adjacent to the Excel alternative page; cover Excel for the web, Office Home one-time purchase,
   and free apps honestly.
3. **"Open xlsx on an older Mac" (macOS 14 Sonoma)**: Numbers now needs macOS 26, so owners of
   older Macs are a real, under-served audience.
4. **Function landing pages for the top 10 functions** (`/guides/vlookup-in-italian/` → CERCA.VERT,
   SOMMA.SE, SE.ERRORE…), each with examples in both syntaxes. Only if the translation page performs.
5. **"CSV with semicolons on Mac"** as its own short page if Search Console shows that sub-query
   bringing impressions to the CSV guide.
6. **German, Spanish, French locales** of the site: the product already speaks those formula
   languages, and "Excel Alternative Mac kostenlos" (t3n covers similar apps) is an obvious next market.
7. **Changelog / release notes page** on the site (fresh content, "what's new in Foglio 1.1").
8. **Developer posts** for the technology audience (HN, Reddit r/rust, r/macapps): "Making
   IronCalc's VLOOKUP 1,300× faster", "A spreadsheet in 7.5 MB: Swift + Rust without Xcode".
   These earn backlinks, which the commercial pages need.

## Sources consulted

Competitor facts (also listed on the comparison page):

- Microsoft 365 plans, US: https://www.microsoft.com/en-us/microsoft-365/buy/compare-all-microsoft-365-products
- Microsoft 365 plans, Italy: https://www.microsoft.com/it-it/microsoft-365/buy/compare-all-microsoft-365-products
- Excel on the Mac App Store: https://apps.apple.com/us/app/microsoft-excel/id462058435?mt=12
- Microsoft required diagnostic data: https://learn.microsoft.com/en-us/microsoft-365-apps/privacy/required-diagnostic-data
- Numbers on the App Store: https://apps.apple.com/us/app/numbers-make-spreadsheets/id361304891
- About Apple Creator Studio: https://support.apple.com/en-ca/125029
- Apple Creator Studio Italian price: https://www.telefonino.net/notizie/apple-creator-studio-la-rivoluzione-creativa-parte-da-1299-euro-al-mese/
- Numbers functions help: https://support.apple.com/guide/functions
- LibreOffice download / system requirements: https://www.libreoffice.org/download/download-libreoffice/ , https://www.libreoffice.org/get-help/system-requirements/
- LibreOffice DMG size: HEAD request on download.documentfoundation.org (26.8.2 aarch64, 299,236,406 bytes)
- LibreOffice LAMBDA request: https://www.libreoffice.org/bugzilla/show_bug.cgi?id=138749
- LibreOffice 26.8 "no AI": https://itsfoss.com/news/libreoffice-26-8-release/
- Google Docs offline: https://support.google.com/docs/answer/6388102
- Google Sheets and Office files: https://support.google.com/docs/answer/6055139
- Google Sheets size limits: https://support.google.com/docs/answer/37603

SERP research (examples of what currently ranks):

- EN "best free excel alternative for mac": clickup.com, wps.com, setapp.com, softpicker.com,
  spreadsheetpoint.com, viasocket.com, sourceforge.net.
- IT "aprire file xlsx su mac senza excel": aranzulla.it, navigaweb.net, onlyoffice.com/blog/it,
  clickup.com/it, canva.com (online viewer).
- EN "open xls file on mac": discussions.apple.com threads (Numbers "unsupported version of Excel",
  HTML disguised as .xls), alphr.com, thebricks.com, wildandfreetools.com.
