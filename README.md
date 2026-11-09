<p align="center">
  <img src="assets/icon-1024.png" width="160" alt="Foglio icon">
</p>

<h1 align="center">Foglio</h1>

<p align="center">
  A lightweight, native spreadsheet for macOS.<br>
  Excel-like, open formats, tiny footprint.
</p>

---

*Foglio* is Italian for "sheet" (of paper). It is an open-source spreadsheet app for the Mac,
written in Swift/AppKit on top of a Rust calculation core. The aim is simple: open and edit
everyday spreadsheets quickly, feel at home on macOS, and stay small.

> **Status: 1.0 preview.** Foglio handles everyday spreadsheets end to end. Keep backups of
> important files: pivot tables, macros and comments are not supported yet (see below).

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
  copy/paste with relative references (and plain text from/to other apps), Paste Values.
- Formatting: font size, bold/italic/underline/strikethrough, text and fill colours, borders,
  alignment, wrap text (rows grow automatically), merge & center, number formats
  (General, Number, Currency, Accounting, Date, Time, %, Fraction, Scientific, Text, custom codes)
  with a *Format Cells* dialog (⌘1); conditional formatting from Excel files is displayed.
- Rows and columns: resize by dragging (double-click to autofit), insert, delete, hide/unhide;
  freeze panes; zoom 25–400 % (pinch, ⌘+ / ⌘−); gridlines toggle.
- Data: sort A→Z / Z→A (with header detection), AutoFilter with value checklists, Find & Replace,
  Go To; conditional formatting rules (greater/less/between/equal, text contains, duplicates,
  top/bottom N, above/below average, colour scales); Format Painter.
- **Formulas in your language**: on an Italian Mac you type `=SOMMA(A1:A10;B2)`, `SE`, `CERCA.VERT`
  with `;` separators and decimal commas, exactly like Excel in Italian. Files always store formulas in
  Excel's standard (English) form, so they open everywhere. Also German, Spanish, French, English.
- UI in English and Italian.

**Files**
- `.xlsx` read/write with formatting (fonts, fills, borders, number formats, merges, column widths,
  row heights, frozen panes, multiple sheets).
- Opens `.xlsm` (macros are not run), `.xls`, `.xlsb`, `.ods` (values, formulas and dates), and
  `.csv` / `.tsv` / `.txt` with automatic encoding, delimiter and decimal-separator detection.
- Charts (column, bar, line, pie, doughnut, area, scatter; stacked variants): Insert ▸ Chart
  from the selection, move/resize on the sheet, properties sheet; read from and saved to `.xlsx`.
- Saves `.xlsx`, exports `.csv` (UTF-8 with BOM; `;` delimiter in decimal-comma locales) and PDF.

**Formulas** — ~500 Excel functions via a patched fork of the [IronCalc](https://github.com/ironcalc/IronCalc) engine
(incremental recalculation, indexed lookups, Excel-compatibility fixes — see [third_party/README.md](third_party/README.md)),
including XLOOKUP, FILTER/SORT/UNIQUE, LET/LAMBDA, SUMIFS, the date, text, statistical and financial
families. See [docs/FUNCTIONS.md](docs/FUNCTIONS.md) for the compatibility audit.

**Small and fast** (measured on an M4, see [docs/PERFORMANCE.md](docs/PERFORMANCE.md))

| | Foglio | LibreOffice | Excel |
|---|---|---|---|
| Download (DMG, universal) | 5.4 MB | ~330 MB | ~1 GB |
| App size | 17 MB (Apple silicon + Intel) | ~780 MB | 1–2 GB |
| Memory, empty sheet | ~40 MB | ~360 MB | — |
| Launch to first frame (warm) | ~0.2 s | seconds | seconds |
| Scrolling a 20k-row sheet | ~3 ms per frame, no dropped frames | | |
| Open a 100k-row xlsx (300k formulas) | 0.9 s, ~113 MB | | |
| One edit, 1,000 VLOOKUPs over 20k rows | ~3 ms (incremental recalculation) | | |

**Not yet supported**: pivot tables, comments/notes, data validation, images, macros,
password-protected files, data bars/icon sets.

## Testing

```sh
scripts/build.sh --arm64-only && scripts/ui_tests.sh   # 27 UI tests driven by real keyboard/mouse events
(cd core && cargo test --release)                       # file-format tests
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
| Zoom | ⌘+ / ⌘− / ⌘0, pinch |
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

- App Mac nativa (AppKit), niente Electron.
- Apre file `.xlsx`, `.xls`, `.ods` e `.csv` (il supporto ai formati è in fase di sviluppo).
- Circa 400 funzioni di Excel grazie a IronCalc.
- Un'unica app universale (Apple silicon e Intel) di pochi megabyte.

Il progetto è nelle prime fasi di sviluppo: molte funzioni sono ancora in lavorazione.

**Compilazione:** installa gli Xcode Command Line Tools (`xcode-select --install`) e Rust con
Homebrew (`brew install rustup`, poi `rustup default stable` e
`rustup target add aarch64-apple-darwin x86_64-apple-darwin`). Quindi esegui
`scripts/build.sh` per creare `build/Foglio.app`, oppure `scripts/package.sh` per ottenere
l'immagine disco `build/Foglio-<versione>.dmg`.

Licenza: MIT oppure Apache-2.0, a tua scelta. I contributi sono benvenuti!
