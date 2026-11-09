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

> **Status: early development.** Foglio is a young project and many features are still being
> built. Expect rough edges, and please don't trust it with your only copy of important data yet.

## Features

- **Native macOS app** — AppKit UI with a custom grid view, no Electron, no web views.
- **Open formats** — works with `.xlsx`, and reads `.xls`, `.ods` and `.csv`
  (format support is still being extended).
- **Excel-compatible formulas** — around 400 Excel functions, provided by the
  [IronCalc](https://github.com/ironcalc/IronCalc) engine.
- **Tiny footprint** — a single universal (Apple silicon + Intel) app of a few megabytes
  that starts instantly.
- **Free and open source** — dual-licensed MIT / Apache-2.0.

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
