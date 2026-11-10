<p align="center">
  <img src="assets/icon-1024.png" width="160" alt="Foglio icon">
</p>

<h1 align="center">Foglio</h1>

<p align="center">
  A free, lightweight, native spreadsheet for macOS that opens your Excel files.<br>
  7.5 MB download · opens in 0.24 s · no account, no subscription.
</p>

<p align="center">
  <a href="https://github.com/GetFoglio/foglio/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/GetFoglio/foglio?label=release&color=1f9d6b"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1f9d6b">
  <img alt="Apple silicon and Intel" src="https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-1f9d6b">
  <a href="#license"><img alt="License: MIT or Apache-2.0" src="https://img.shields.io/badge/license-MIT%20%2F%20Apache--2.0-1f9d6b"></a>
  <a href="https://github.com/GetFoglio/foglio/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/GetFoglio/foglio?style=flat&color=e3a008"></a>
</p>

<p align="center">
  <a href="https://github.com/GetFoglio/foglio/releases/download/v1.0.2/Foglio-1.0.2.dmg"><b>Download Foglio 1.0.2</b></a> ·
  <a href="https://getfoglio.app">getfoglio.app</a> ·
  <a href="https://github.com/GetFoglio/foglio/releases">All releases</a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
    <img src="docs/screenshot-light.png" width="860" alt="Foglio on macOS: a sales sheet with formulas and a column chart">
  </picture>
</p>

---

*Foglio* is Italian for "sheet" (of paper). It is an open-source spreadsheet app for the Mac,
written in Swift/AppKit on top of a Rust calculation core. The aim is simple: open and edit
everyday spreadsheets quickly, feel at home on macOS, and stay small.

Foglio does not try to be Excel. It is the app you open when you need to read, fix or fill in a
spreadsheet: native, fast, small, and able to open the Excel files you receive.

> **Latest version: 1.0.2** (November 9, 2026). Foglio handles everyday spreadsheets end to end.
> Keep backups of important files: pivot tables, macros and password-protected files are not
> supported yet (see [below](#not-yet-supported)).

If Foglio is useful to you, a ⭐ on GitHub helps other Mac users find it.

## What's new

**1.0.2** — more Excel files open exactly as they were saved, and stay that way when you save them.
- Horizontal scroll bar fixed (it was drawn as a tiny vertical bar in the bottom-right corner).
- Sheet zoom, "show zeros" off, default row height and AutoFilter (ranges and hidden values) are
  read from the file and saved back; each sheet keeps its own zoom.
- Grouped pictures (catalogues, price lists) are saved back as groups and reopen in place.

**1.0.1** — fixes for real-world Excel files.
- The grid, headers, charts and pictures are redrawn live while you resize the window.
- Frozen panes saved by Excel as `frozenSplit` are frozen; borders of merged cells are drawn only
  around the merge; currency symbols go where the format puts them (`13,75 €`, `[$CHF-807]`).
- Pictures inside groups are placed where Excel places them, with smoother scrolling on sheets
  with hundreds of pictures; the status-bar zoom follows pinch and ⌘-scroll.

**1.0** — first public release. Full notes and SHA-256 checksums on the
[releases page](https://github.com/GetFoglio/foglio/releases).

## Features

**Feels like Excel, behaves like a Mac app**
- Native AppKit UI: custom high-performance grid, real macOS documents (Open Recent, Save/Save As,
  Revert, Duplicate, window tabs, full screen, dark mode, Print and Export PDF).
- Excel-style toolbar, formula bar with Name Box (type `B12` or `Sheet2!A1:C9` to jump), sheet tabs
  (add, rename, duplicate, move, hide, delete) and a status bar with Average / Count / Min / Max / Sum.
- In-cell editing with Excel's Enter / Edit / **Point** modes: while typing a formula, click or use the
  arrow keys to insert references; references are colour-coded in the formula and on the grid.
- Function autocomplete with descriptions, argument hints (current argument in bold),
  an *Insert Function* browser with all ~500 functions, and F4 to cycle `$` references.
- Fill handle (drag, or double-click to fill down), Fill Down ⌘D / Right ⌘R, AutoSum,
  copy/paste with relative references (and plain text from/to other apps), Paste Special (⌃⌘V:
  values, formats, transpose), paste repeated over a larger selection, drag the selection border
  to move cells (⌥ to copy), Insert/Delete Cells with shift (⌃I / ⌘−), Repeat (⌘Y),
  AutoComplete of text already in the column, Show Formulas (⌃`).
- Formatting: font family and size, bold/italic/underline/strikethrough, text and fill colours (Excel palette), borders,
  alignment, wrap text (rows grow automatically), merge & center, number formats
  (General, Number, Currency, Accounting, Date, Time, %, Fraction, Scientific, Text, custom codes)
  with a *Format Cells* dialog (⌘1); conditional formatting from Excel files is displayed.
- Rows and columns: resize by dragging (double-click to autofit), insert, delete, hide/unhide;
  freeze panes; zoom 25–400 % (pinch, ⌥⌘+ / ⌥⌘−); gridlines toggle; sheet tab colours and drag-to-reorder.
- Data: sort A→Z / Z→A and multi-level Sort dialog (with header detection), AutoFilter with value
  checklists, Find & Replace with Find All, Go To, Remove Duplicates, Text to Columns,
  **Data Validation** (lists with in-cell dropdown, numbers, dates, text length, custom; input
  messages; Stop/Warning/Information alerts), **Summarize by** (a live SUMIFS/COUNTIFS summary sheet,
  a light pivot table), defined names (Name Box, Define Name, Name Manager); conditional formatting rules (greater/less/between/equal, text contains, duplicates,
  top/bottom N, above/below average, colour scales); Format Painter.
- **Formulas in your language**: on an Italian Mac you type `=SOMMA(A1:A10;B2)`, `SE`, `CERCA.VERT`
  with `;` separators and decimal commas, exactly like Excel in Italian. Files always store formulas in
  Excel's standard (English) form, so they open everywhere. Also German, Spanish, French, English.
- **Comments/notes** with red-corner indicators and hover popups; **hyperlinks** (⌘K, ⌘-click to open).
- **Charts** (column, bar, line, pie, doughnut, area, scatter, stacked variants): Insert ▸ Chart or the
  toolbar, move/resize on the sheet, properties sheet; read from and saved to `.xlsx`.
- **Pictures**: Insert ▸ Picture… (several at once), paste an image (⌘V) or drop image files on the grid
  (PNG, JPEG, GIF, TIFF, HEIC, …). Move, resize (corners keep the aspect ratio, ⇧ frees them), nudge with
  the arrow keys, cut/copy/paste, Delete. Format ▸ Picture (and the right-click menu): **Crop** (Excel-style
  crop handles; drag inside to move the image under the frame; Return/Esc/click outside to finish), Reset
  Crop, Reset Size, **Place in Cell** / Place over Cells, Bring Forward/Send Backward (shared with charts),
  Alt Text…, Change Picture…, **Compress Pictures…** (selected picture or all; delete cropped areas; high
  fidelity, 220, 150 or 96 ppi of the displayed size; photos become JPEG, transparent or flat-colour images
  PNG; shows the size before and after). Every change is one undo step.
- Printing: fit all columns on one page, optional gridlines, orientation and paper from the Print panel;
  pictures and charts are printed (and exported to PDF) with the cells.
- UI in English and Italian.

**Files**
- `.xlsx` read/write with formatting (fonts, fills, borders, number formats, merges, column widths,
  row heights, frozen panes, multiple sheets).
- Opens `.xlsm` (macros are not run), `.xls`, `.xlsb`, `.ods` (values, formulas and dates), and
  `.csv` / `.tsv` / `.txt` with automatic encoding, delimiter and decimal-separator detection.
- Comments, data validation, hyperlinks, tab colours, defined names, conditional formatting, charts
  and pictures are read from and written to `.xlsx`.
- Pictures in `.xlsx`: `xl/media/imageN.png|jpeg` (an image used several times is stored once),
  `<xdr:pic>` with cropping (`a:srcRect`), alt text and `editAs` (move and size with cells / move only /
  don't move); charts and pictures share the sheet's drawing part and keep their stacking order.
  Pictures written by Excel, LibreOffice, openpyxl, Apache POI (two-cell, one-cell and absolute anchors)
  are read. EMF/WMF pictures (old Office clip art, MathType equations, pasted Visio/Stata/chart
  pictures) are drawn by a built-in metafile player (`app/Sources/Metafile.swift`: shapes, paths, pens,
  brushes, text in any Windows charset incl. Symbol and CJK, embedded bitmaps; EMF+-only records are
  skipped), can be inserted from files and are saved back unchanged. *Place in Cell* is saved
  as a picture that moves and sizes with its cell (not Excel 365's rich-value "picture in cell" format,
  so it opens in every Excel as a normal picture over that cell); Excel 365 pictures in cells
  (`xl/richData`) are read as pictures placed in their cells.
- The sheet's zoom, "show zeros" setting, default row height and AutoFilter (range and value lists) are read
  from and saved to `.xlsx`; pictures that were grouped in the file are saved back as a group.
- Saves `.xlsx`, exports `.csv` (UTF-8 with BOM; `;` delimiter in decimal-comma locales) and PDF.

**Formulas** — ~500 Excel functions via a patched fork of the [IronCalc](https://github.com/ironcalc/IronCalc) engine
(incremental recalculation, indexed lookups, Excel-compatibility fixes — see [third_party/README.md](third_party/README.md)),
including XLOOKUP, FILTER/SORT/UNIQUE, LET/LAMBDA, SUMIFS, the date, text, statistical and financial
families. See [docs/FUNCTIONS.md](docs/FUNCTIONS.md) for the compatibility audit.

### Not yet supported

Real pivot tables (use *Summarize by*), shapes/text boxes/SmartArt (skipped when
reading), picture effects (borders, shadows, rotation), macros, password-protected files, data
bars/icon sets, sparklines, threaded comments (shown as plain notes).

## Speed and size

Measured on a MacBook Air with an M4 processor, 16 GB, macOS 27 (release builds).
Details and the benchmark harness: [docs/PERFORMANCE.md](docs/PERFORMANCE.md).

| | Foglio 1.0.x |
|---|---|
| Download (DMG, universal) | **7.5 MB** |
| App size on disk | 19 MB (Apple silicon + Intel in one app) |
| Launch to first frame (warm) | **~0.24 s** |
| Memory, empty sheet | ~58 MB (`footprint`), 0 % CPU when idle |
| Open a 100k-row `.xlsx` (300k formulas) | 1.1 s, ~171 MB |
| One edit on that workbook (incremental recalculation) | **~16 ms** |
| Full recalculation of that workbook | ~64 ms |

For comparison, the Mac App Store lists Microsoft Excel at about 1.2 GB and Numbers at about 661 MB;
the LibreOffice DMG is about 299 MB (November 2026).

**The engine work.** Foglio uses a patched fork of IronCalc 0.9.1. Same formulas, same results,
much less waiting:

| 1,000 formulas over a 10,000-row table | IronCalc 0.9.1 | Foglio |
|---|---|---|
| `VLOOKUP(k, A:B, 2, FALSE)` | 1,703 ms | **1.3 ms** |
| `XLOOKUP(k, A, B)` | 1,614 ms | **0.8 ms** |
| `INDEX(B, MATCH(k, A, 0))` | 92 ms | **0.9 ms** |

| Workbook | IronCalc 0.9.1 | Foglio |
|---|---|---|
| Edit a cell, 100k rows + 1,000 VLOOKUPs | 18.6 s | **16 ms** |
| Edit a cell, 300k rows (900k formulas) | 280 ms | **36 ms** |
| Open a workbook with 3,264 whole-column VLOOKUPs (Apache POI test file) | 11 s | **91 ms** |

## Tests and compatibility

| Suite | What it checks | Result (1.0.2) |
|---|---|---|
| UI tests (`scripts/ui_tests.sh`) | The real app driven by keyboard and mouse events: editing, selection drags, fill, copy/paste, sort, filter, charts, pictures, frozen panes, zoom, save and reopen | **78 / 78** |
| Core tests (`core/`) | File import/export round-trips on synthetic fixtures | **60 / 60** |
| Excel function audit ([docs/FUNCTIONS.md](docs/FUNCTIONS.md)) | 195 common functions against Excel's documented results | **191 OK**, 1 wrong (TREND), 3 missing (AGGREGATE, GROUPBY, PIVOTBY) |
| Real-world files (`scripts/corpus_test.py`) | Opens each of the 783 `.xls`/`.xlsx`/`.xlsm` files of Apache POI's test corpus (Excel files from bug reports, plus deliberately broken ones) in the real app | **738 open**, 0 crashes, 0 hangs. The other 45 are refused with a clear message: 33 fuzzer/malformed/XML-bomb files, 9 password-protected, 3 in the pre-1997 Excel 4 format |
| Formula values | Every formula of 593 `.xlsx`/`.xlsm` files, before and after the engine changes | identical |
| Incremental recalculation | 40 random edits on each of 242 Excel-made workbooks (~7,500 recalculations) against a full recalculation | 0 differences |
| IronCalc's own suites | 3,092 engine tests | 3,085 pass; the 7 failures also fail on unmodified upstream (date-dependent templates and one serialization test) |

Run them:

```sh
scripts/build.sh --arm64-only && scripts/ui_tests.sh   # UI tests driven by real keyboard/mouse events
(cd core && cargo test --release)                       # file-format tests
scripts/corpus_test.py <folder-of-spreadsheets>         # open every file, report crashes and read errors
IRONCALC_CHECK_INCREMENTAL=1 scripts/ui_tests.sh        # also verify every incremental recalculation
```

## Keyboard shortcuts (Excel for Mac conventions)

| Action | Keys |
|---|---|
| Edit cell / new line in cell | F2, ⌥↩ / ⌥↩ while editing |
| Confirm and move down / right / up | ↩ / ⇥ / ⇧↩ |
| Fill selection with the entry | ⌘↩ |
| Jump to edge of data, extend | ⌘ arrow, ⇧⌘ arrow |
| Select region / whole sheet | ⌘A, ⌘A again |
| Select row / column | ⇧Space / ⌃Space |
| Cycle absolute references | F4 |
| Format Cells | ⌘1 |
| Fill Down / Right | ⌘D / ⌘R |
| Paste Values | ⌥⇧⌘V |
| AutoSum | ⇧⌘T |
| Filter | ⇧⌘F |
| Find / Replace / Go To | ⌘F / ⌥⌘F / ⌃G |
| Insert date / time | ⌃; / ⌘; |
| Zoom | ⌥⌘+ / ⌥⌘− / ⌘0, pinch |
| Paste Special / Repeat | ⌃⌘V / ⌘Y |
| Insert / Delete cells | ⌃I / ⌘− |
| Show formulas | ⌃` |
| New comment / Link | ⇧F2 / ⌘K |
| Number formats | ⌃⇧~ ⌃⇧! ⌃⇧$ ⌃⇧% ⌃⇧# ⌃⇧@ ⌃⇧^ |
| Borders: outline / none | ⌥⌘0 / ⌥⌘− |
| Open a validation list | ⌥↓ |
| Recalculate everything | F9 or ⌘= |
| Next / previous sheet | ⌃PageDown / ⌃PageUp, ⌥→ / ⌥← |
| Format Painter | toolbar brush, then select the target |

## Requirements

- macOS 14 Sonoma or later (Apple silicon or Intel)

## Building from source

You need the Xcode Command Line Tools and a Rust toolchain. Full Xcode is not required.

```sh
# 1. Xcode Command Line Tools (Swift compiler, codesign, hdiutil, …)
xcode-select --install

# 2. Rust via rustup (Homebrew)
brew install rustup
rustup default stable
rustup target add aarch64-apple-darwin x86_64-apple-darwin

# 3. Build the app → build/Foglio.app (universal arm64 + x86_64, ad-hoc signed)
scripts/build.sh                # or: scripts/build.sh --arm64-only  (faster, for development)
open build/Foglio.app

# 4. Package a disk image → build/Foglio-<version>.dmg
scripts/package.sh
```

`scripts/package.sh` builds the app and wraps it in a compressed DMG with an `/Applications`
shortcut, using only Apple's tools (`hdiutil`, `codesign`, `notarytool`). By default the app is
ad-hoc signed, so Gatekeeper will ask for confirmation the first time it is opened
(right-click → **Open** on macOS 14; **System Settings → Privacy & Security → Open Anyway**
on macOS 15 and later). To produce a signed and notarized release:

```sh
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=your-notarytool-profile \
scripts/package.sh
```

The app icon is generated in code; to regenerate `assets/icon-1024.png` and
`assets/Foglio.icns`, run `swift scripts/make_icon.swift`.

## Architecture

```
┌──────────────────────────────────────────────┐
│  app/  — Swift / AppKit shell                │
│  windows, menus, documents, custom grid view │
└──────────────────────┬───────────────────────┘
                       │  C ABI  (core/include/foglio_core.h)
┌──────────────────────▼───────────────────────┐
│  core/ — Rust static library (foglio_core)   │
│  workbook model, formula engine (IronCalc),  │
│  file import/export (calamine, csv, …)       │
└──────────────────────────────────────────────┘
```

- **`core/`** is a Rust crate compiled as a static library. It wraps IronCalc's workbook model
  and exposes a small, plain C interface (`core/include/foglio_core.h`): opening and saving
  files, editing cells, and returning batches of visible cells ready to draw.
- **`app/`** is the Swift/AppKit application. It links the static library directly (via an
  Objective-C bridging header — no frameworks, no FFI generators) and draws the sheet with a
  custom `NSView` grid tuned for fast scrolling over large sheets.
- **`scripts/`** holds the build, packaging and icon scripts. The build uses plain `cargo` and
  `swiftc`; there is no Xcode project.
- The website, [getfoglio.app](https://getfoglio.app), lives in its own repository:
  [Acid236/foglio-site](https://github.com/Acid236/foglio-site).

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

Foglio stands on the shoulders of:

- [IronCalc](https://github.com/ironcalc/IronCalc) — the spreadsheet engine: formula parsing and
  evaluation, the workbook model and `.xlsx` support (MIT / Apache-2.0).
- [calamine](https://github.com/tafia/calamine) — fast reading of `.xls`, `.xlsx` and `.ods`
  files (MIT).
- The many other open-source Rust crates listed in `core/Cargo.toml`.

Foglio is an independent project and is not affiliated with or endorsed by Microsoft, Apple,
or the IronCalc project. "Excel" is a trademark of Microsoft Corporation.

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT license ([LICENSE-MIT](LICENSE-MIT))

at your option. Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in Foglio by you, as defined in the Apache-2.0 license, shall be dual licensed as
above, without any additional terms or conditions.

---

## In italiano

**Foglio** è un'applicazione per fogli di calcolo leggera e nativa per macOS, open source.
È scritta in Swift/AppKit con un motore di calcolo in Rust basato su
[IronCalc](https://github.com/ironcalc/IronCalc), e punta a essere veloce, piccola e
compatibile con Excel.

- App Mac nativa (AppKit), niente Electron. Gratuita, senza account, senza pubblicità.
- Apre e salva `.xlsx`; apre anche `.xlsm`, `.xls`, `.xlsb`, `.ods`, `.csv` e `.tsv`.
- Circa 500 funzioni di Excel (motore IronCalc con patch), scritte nella tua lingua:
  su un Mac in italiano scrivi `=SOMMA(A1:A10;B2)`, `SE`, `CERCA.VERT`.
- Un'unica app universale (Apple silicon e Intel): 7,5 MB da scaricare, si apre in circa 0,24 s,
  circa 58 MB di memoria con un foglio vuoto.
- 1.000 CERCA.VERT su 10.000 righe: 1,3 ms (il motore IronCalc originale impiega 1,7 s).
  Testato su un Mac con processore M4, macOS 27.

Ultima versione: **1.0.2** ([scarica il DMG](https://github.com/GetFoglio/foglio/releases/download/v1.0.2/Foglio-1.0.2.dmg)).
Copre i fogli di calcolo di tutti i giorni. Non supporta ancora tabelle pivot vere,
macro e file protetti da password; tieni un backup dei file importanti. Sito: [getfoglio.app/it](https://getfoglio.app/it/).

**Compilazione:** installa gli Xcode Command Line Tools (`xcode-select --install`) e Rust con
Homebrew (`brew install rustup`, poi `rustup default stable` e
`rustup target add aarch64-apple-darwin x86_64-apple-darwin`). Quindi esegui
`scripts/build.sh` per creare `build/Foglio.app`, oppure `scripts/package.sh` per ottenere
l'immagine disco `build/Foglio-<versione>.dmg`.

Licenza: MIT oppure Apache-2.0, a tua scelta. I contributi sono benvenuti, e se Foglio ti è utile
lascia una ⭐ su GitHub: aiuta altri utenti Mac a trovarlo.
