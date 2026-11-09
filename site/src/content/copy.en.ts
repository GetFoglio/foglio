import type { SiteCopy } from "./types";

export const copyEn: SiteCopy = {
  ui: {
    navCompare: "Compare",
    navTechnology: "Technology",
    navAlternatives: "Alternatives",
    navGuides: "Guides",
    navDownload: "Download",
    navGitHub: "GitHub",
    download: "Download for Mac",
    downloadSub: "Free · macOS 14+ · Apple silicon & Intel · 7.5 MB",
    viewSource: "View source on GitHub",
    readMore: "Read more",
    faqTitle: "Frequently asked questions",
    updated: "Updated",
    languageName: "Italiano",
    skipToContent: "Skip to content",
    footerTagline: "A free, open-source spreadsheet for the Mac. Native, tiny and Excel-compatible.",
    footerLicense: "Foglio is free software, dual-licensed under MIT and Apache-2.0.",
    footerTrademark:
      "Excel is a trademark of Microsoft Corporation. Numbers is a trademark of Apple Inc. Google Sheets is a trademark of Google LLC. LibreOffice is a trademark of The Document Foundation. Foglio is an independent project and is not affiliated with or endorsed by any of them.",
    notFoundTitle: "This sheet is empty",
    notFoundText: "The page you were looking for does not exist or has moved. Try the home page or one of the guides.",
    backHome: "Back to the home page",
    yes: "Yes",
    no: "No",
    partial: "Partly",
  },

  meta: {
    home: {
      title: "Foglio: Free Spreadsheet App for Mac, Excel-Compatible",
      description:
        "Foglio is a free, open-source spreadsheet for macOS. Opens and saves Excel xlsx files, ~500 functions, native and tiny: a 7.5 MB download. No account.",
      ogTitle: "Foglio — a free, native, open-source spreadsheet for the Mac",
    },
    compare: {
      title: "Foglio vs Excel vs Numbers vs LibreOffice vs Sheets",
      description:
        "An honest side-by-side of Mac spreadsheet apps: price, size, speed, xlsx support, macros, pivot tables, collaboration and privacy. Sources linked.",
    },
    technology: {
      title: "How Foglio Is Built: Swift, AppKit and Rust | Foglio",
      description:
        "Inside Foglio: a native Swift/AppKit app over a Rust engine (a patched IronCalc fork). Why it downloads at 7.5 MB, opens in 0.24 s and recalculates fast.",
    },
    download: {
      title: "Download Foglio for Mac: Free Spreadsheet App | Foglio",
      description:
        "Download Foglio 1.0, a free spreadsheet app for macOS 14 or later. Universal for Apple silicon and Intel, a 7.5 MB disk image. Install steps inside.",
    },
    alternatives: {
      title: "Excel, Numbers and Google Sheets Alternatives | Foglio",
      description:
        "Looking for an alternative to Excel, Numbers, LibreOffice Calc or Google Sheets on the Mac? Honest guides on when Foglio fits and when it does not.",
    },
    guides: {
      title: "Mac Spreadsheet Guides: Open xlsx, xls and CSV | Foglio",
      description:
        "Practical how-to guides for spreadsheets on the Mac: open Excel and CSV files without Excel, fix encodings, use formulas in your language, and more.",
    },
  },

  home: {
    eyebrow: "Free · Open source · Native macOS",
    h1: "The free spreadsheet for Mac that opens your Excel files",
    subtitle:
      "Foglio is a small, fast, native Mac app for everyday spreadsheets. It opens and saves `.xlsx`, opens `.xls`, `.ods` and `.csv`, speaks ~500 Excel functions, and costs nothing: no subscription, no account, no ads.",
    badges: [
      "Free forever, MIT / Apache-2.0",
      "7.5 MB download, launches in 0.24 s",
      "Native Swift/AppKit, no Electron",
      "No account, no telemetry",
    ],
    statLabels: {
      download: "Download size",
      launch: "Launch to first frame",
      memory: "Memory with an empty sheet",
      open100k: "Open a 100,000-row xlsx",
      recalc: "Edit + recalculate 300k formulas",
      price: "Price, forever",
    },
    featuresTitle: "Everything you need for everyday spreadsheets",
    featuresIntro:
      "Foglio covers the work most people actually do in a spreadsheet: lists, budgets, invoices, reports, data from other people's Excel files. It feels like Excel and behaves like a Mac app.",
    features: [
      {
        icon: "file",
        title: "Opens Excel files",
        text: "Reads and writes `.xlsx` with formatting, charts, pictures, comments and validation. Opens `.xls`, `.xlsb`, `.xlsm`, `.ods`, `.csv` and `.tsv` too.",
      },
      {
        icon: "function",
        title: "~500 Excel functions",
        text: "SUMIFS, XLOOKUP, FILTER, SORT, UNIQUE, LET, LAMBDA, dates, text, statistics and finance. 191 of 195 audited functions match Excel on every test case.",
      },
      {
        icon: "globe",
        title: "Formulas in your language",
        text: "On an Italian Mac type `=SOMMA(A1:A10)` or `CERCA.VERT` with `;` and decimal commas. Also German, Spanish and French. Files stay standard Excel.",
      },
      {
        icon: "bolt",
        title: "Fast on big sheets",
        text: "A 100,000-row workbook with 300,000 formulas opens in 1.1 s and recalculates after an edit in 16 ms, thanks to incremental recalculation.",
      },
      {
        icon: "feather",
        title: "Tiny and light",
        text: "A 7.5 MB download, 19 MB installed, about 58 MB of memory with an empty sheet and 0 % CPU when idle. Your fans stay quiet.",
      },
      {
        icon: "apple",
        title: "A real Mac app",
        text: "Written in Swift and AppKit: Open Recent, window tabs, dark mode, Print and Export PDF, pinch to zoom, Excel for Mac keyboard shortcuts.",
      },
      {
        icon: "chart",
        title: "Charts and pictures",
        text: "Column, bar, line, pie, doughnut, area and scatter charts, saved to `.xlsx`. Insert, crop and compress pictures; even old EMF/WMF clip art renders.",
      },
      {
        icon: "filter",
        title: "Data tools",
        text: "Sort, AutoFilter, Find & Replace, Remove Duplicates, Text to Columns, data validation dropdowns, conditional formatting and a light pivot (Summarize by).",
      },
      {
        icon: "lock",
        title: "Private by design",
        text: "No account, no ads, no analytics. Foglio makes no network connections of its own: your files stay on your Mac.",
      },
    ],
    speedTitle: "Small enough to forget it is there",
    speedIntro:
      "Foglio is built without a browser engine, a Java runtime or a bundled framework. That is why it downloads in seconds and opens before you can move the mouse.",
    speedNote:
      "Foglio figures measured on a MacBook Air M4 (16 GB), macOS 27, Foglio 1.0, November 2026: medians of several runs, memory as reported by `footprint`. Competitor sizes are the download or installed sizes listed by their stores and download pages in November 2026.",
    freeTitle: "Free, and it stays free",
    freeText: [
      "Foglio has no price, no trial, no subscription and no paid tier. You do not need an Apple ID, a Microsoft account or a Google account to use it, and there are no ads.",
      "The source code is on [GitHub](https://github.com/Acid236/foglio) under the MIT and Apache-2.0 licenses, so anyone can read it, build it, fix it or fork it. Your spreadsheets are standard `.xlsx` files that open in Excel, Numbers, LibreOffice and Google Sheets: no lock-in.",
    ],
    compareTitle: "How it compares",
    compareText:
      "Excel has more features, Google Sheets has live collaboration, Numbers has beautiful templates. Foglio is the free, light, native option that still opens Excel files properly. See the [full comparison](/compare/) for the details, including where the others win.",
    techTitle: "Built like a Mac app should be",
    techText:
      "A Swift/AppKit interface with a custom grid, on top of a Rust calculation engine (a patched fork of IronCalc) linked in as a plain static library. Read [how Foglio is built](/technology/) and why that makes it small and fast.",
    formatsTitle: "Opens the files people send you",
    formatsText:
      "`.xlsx` and `.xlsm` from Excel, old `.xls` and binary `.xlsb`, `.ods` from LibreOffice, and `.csv` / `.tsv` with automatic detection of encoding, delimiter and decimal separator. Saves `.xlsx`, exports CSV and PDF. See the guides on [opening xlsx files without Excel](/guides/open-xlsx-on-mac-without-excel/), [opening old .xls files](/guides/open-xls-on-mac/) and [opening CSV files on a Mac](/guides/open-csv-on-mac/).",
    alternativesTitle: "Switching from something else?",
    alternativesText:
      "Honest notes for people coming from [Excel for Mac](/alternatives/excel-for-mac/), [Numbers](/alternatives/numbers/), [LibreOffice Calc](/alternatives/libreoffice/) or [Google Sheets](/alternatives/google-sheets/), including when you should keep using them. All of them are on the [alternatives page](/alternatives/).",
    ctaTitle: "Try it on your own spreadsheets",
    ctaText:
      "It is a 7.5 MB download and it costs nothing. Foglio 1.0 is a first release, so keep backups of important files while you try it.",
    faq: [
      {
        q: "Is Foglio really free?",
        a: "Yes. There is no price, no trial period, no subscription, no in-app purchase and no ads. Foglio is open-source software under the MIT and Apache-2.0 licenses.",
      },
      {
        q: "Can Foglio open and save Excel files?",
        a: "Yes. It reads and writes `.xlsx` with formatting, charts, pictures, comments, data validation and conditional formatting. It also opens `.xls`, `.xlsb`, `.xlsm` and `.ods`, and CSV/TSV text files. It saves as `.xlsx`, and exports CSV and PDF.",
      },
      {
        q: "Is it a full replacement for Microsoft Excel?",
        a: "For everyday spreadsheets, often yes. For some work, no: Foglio does not run macros (VBA), has no real pivot tables (it offers a lighter *Summarize by* instead), skips shapes and SmartArt, and cannot open password-protected files. The [comparison](/compare/) lists the differences.",
      },
      {
        q: "Which Macs does it run on?",
        a: "Any Mac with macOS 14 Sonoma or later, Apple silicon or Intel. It is a single universal app.",
      },
      {
        q: "Why does macOS say Foglio is from an unidentified developer?",
        a: "Foglio 1.0 is not signed with a paid Apple Developer ID, so the first time you open it macOS asks for confirmation. On macOS 15 or later go to System Settings ▸ Privacy & Security and click **Open Anyway**; on macOS 14 right-click the app and choose **Open**. The [download page](/download/) explains each step.",
      },
      {
        q: "Does Foglio collect data or need an account?",
        a: "No. There is no account, no sign-in, no analytics and no telemetry. Foglio makes no network connections of its own; it only opens a web link when you click a hyperlink in a cell.",
      },
      {
        q: "Can I type formulas in Italian, German, Spanish or French?",
        a: "Yes. Foglio follows your Mac's language and region: on an Italian Mac you type `=SOMMA(A1:A10;B2)` with semicolons and decimal commas, just like Excel in Italian. Files always store the standard English form, so they open correctly everywhere. See the [Italian–English function list](/guides/excel-functions-italian-english/).",
      },
      {
        q: "Is Foglio finished?",
        a: "Foglio 1.0 handles everyday spreadsheets end to end and is covered by 69 automated UI tests, but it is a first release. Keep backups of important files and report problems on [GitHub](https://github.com/Acid236/foglio/issues).",
      },
    ],
  },

  compare: {
    h1: "Foglio vs Excel, Numbers, LibreOffice and Google Sheets",
    intro: [
      "There is no single best spreadsheet for the Mac. There is the one that fits what you do. This page puts Foglio next to the four apps Mac users most often choose between, and it is deliberately honest: where another app is better, the table says so.",
      "In short: **Excel** is the most complete and the most expensive; **Numbers** is free and pretty but converts Excel files; **LibreOffice Calc** is free and powerful but large and not a native Mac app; **Google Sheets** is free and collaborative but lives in a browser and needs a Google account. **Foglio** is free, open source, tiny and native, and edits `.xlsx` directly, with fewer advanced features than Excel.",
    ],
    tableTitle: "Side-by-side comparison",
    tableNote:
      "Prices and features checked on the vendors' own pages in November 2026 (sources below); prices are US list prices and vary by country. Foglio's figures were measured on a MacBook Air M4, macOS 27, Foglio 1.0.",
    sections: [
      {
        heading: "Which one should you choose?",
        body: [
          "Pick the tool for the job, not the brand. Most people only need a fraction of what any of these apps can do.",
        ],
        bullets: [
          "**Choose Foglio** if you want a free, fast, private app that opens and saves Excel files on your Mac without an account or subscription.",
          "**Choose Excel** if you rely on macros (VBA), Power Query, real pivot tables, advanced charts, or you must match your company's files to the pixel.",
          "**Choose Numbers** if you build documents that should look beautiful, mostly for yourself, and you live in Apple's ecosystem, including iPhone and iPad.",
          "**Choose LibreOffice Calc** if you need a free app with pivot tables, macros and a huge feature set, and do not mind a large, non-native app.",
          "**Choose Google Sheets** if several people edit the same sheet at the same time and you are comfortable working in a browser with a Google account.",
        ],
      },
      {
        heading: "Where Foglio wins",
        body: [
          "Foglio is the smallest app in this comparison by a wide margin: a 7.5 MB download against hundreds of megabytes or gigabytes for the desktop alternatives. It opens to a usable window in 0.24 s, uses about 58 MB of memory with an empty sheet and sits at 0 % CPU when idle.",
          "It is free with no conditions, open source, and works completely offline with no account. Unlike Numbers it edits `.xlsx` files in place instead of converting them, and on an Italian, German, Spanish or French Mac you type formulas with the same localized function names Excel uses.",
        ],
      },
      {
        heading: "Where the others win",
        body: [
          "Excel is far more complete: macros, Power Query, real pivot tables, many more chart types, and the reference behaviour for every Excel file. LibreOffice also has pivot tables and macros, plus a drawing layer and many more import and export formats. Google Sheets has the best real-time collaboration and runs on any device with a browser. Numbers and Excel have iPhone and iPad apps; Foglio is Mac-only.",
          "Foglio is a 1.0 release by a small open-source project. The big suites have decades of polish behind them. If a file matters, keep a backup.",
        ],
      },
    ],
    faq: [
      {
        q: "What is the best free alternative to Excel on a Mac?",
        a: "It depends on what you need. Foglio is the lightest free option that edits `.xlsx` directly. LibreOffice Calc is the most feature-complete free desktop app. Google Sheets is best for collaboration. Numbers is pre-installed and free but converts Excel files to its own format. Our [roundup of free spreadsheet apps](/guides/free-spreadsheet-apps-for-mac/) covers more options.",
      },
      {
        q: "Does Foglio support macros or VBA?",
        a: "No. Foglio opens `.xlsm` files but does not run their macros. If your work depends on VBA, use Microsoft Excel; LibreOffice can run some VBA too.",
      },
      {
        q: "Does Foglio have pivot tables?",
        a: "Not real pivot tables yet. *Summarize by* builds a live summary sheet with SUMIFS and COUNTIFS formulas, which covers simple pivots. Excel, LibreOffice, Numbers and Google Sheets all have pivot tables.",
      },
      {
        q: "Can several people edit a Foglio file at the same time?",
        a: "No. Foglio is a desktop app for one person at a time. For live co-editing, Google Sheets or Excel with OneDrive are the better choice.",
      },
      {
        q: "Are the competitor prices current?",
        a: "They were checked on the vendors' pages in November 2026 and are US list prices. Prices change and vary by country, so follow the source links before buying.",
      },
    ],
  },

  technology: {
    h1: "How Foglio is built, and why that makes it small and fast",
    intro: [
      "Most modern desktop apps ship a copy of a web browser, a Java runtime or a big cross-platform framework. Foglio ships none of them. It is a native Mac app in Swift and AppKit, with the spreadsheet engine written in Rust and linked straight into the app.",
      "This page explains the architecture twice: first in plain words, then in enough detail for a developer to find their way around the [source code](https://github.com/Acid236/foglio).",
    ],
    sections: [
      {
        heading: "The short version",
        body: [
          "Think of Foglio as two parts. The part you see (windows, menus, the grid of cells) is written with Apple's own tools, so it looks and behaves like every other Mac app. The part that does the maths (reading files, understanding formulas, recalculating) is a separate engine written in Rust, a language that produces very fast, compact programs.",
          "The two parts talk through a small, plain interface. Nothing sits in between: no hidden browser, no virtual machine, no runtime to download. That is why the whole app is a 7.5 MB download, launches in 0.24 s and needs about 58 MB of memory with an empty sheet.",
        ],
      },
      {
        heading: "The Mac app: Swift and AppKit",
        body: [
          "The interface is written in Swift on AppKit, the framework behind Finder and most of the Mac's own apps. Documents are real macOS documents, so Open Recent, Save As, Revert, Duplicate, window tabs, full screen, dark mode, printing and Export PDF work the way you expect.",
          "The sheet itself is a custom `NSView` grid, not a table control. It asks the engine only for the cells that are visible, in batches ready to draw, which keeps scrolling smooth on sheets with hundreds of thousands of rows. Charts, pictures and the formula bar are drawn by the app too.",
          "Foglio also contains its own player for EMF and WMF metafiles, the vector picture format of older Office documents (clip art, MathType equations, pasted Visio diagrams). Pictures that other Mac apps show as blank boxes are drawn properly and saved back unchanged.",
        ],
      },
      {
        heading: "The engine: Rust and a patched IronCalc",
        body: [
          "Formulas are parsed and evaluated by [IronCalc](https://github.com/ironcalc/IronCalc), an open-source spreadsheet engine in Rust. Foglio uses a patched fork of IronCalc 0.9.1 with every change marked and documented in the repository.",
          "The fork adds **incremental recalculation**: when you edit a cell, only the formulas that depend on it are recalculated, instead of the whole workbook. On a workbook with 100,000 rows and 300,000 formulas, an edit takes 16 ms; a full recalculation takes 64 ms.",
          "It also adds **indexed lookups**. The first VLOOKUP, MATCH or XLOOKUP into a range reads it once and builds a hash index; later lookups are a single probe. 1,000 exact VLOOKUPs over 10,000 rows went from 1,703 ms in upstream IronCalc to 1.3 ms in Foglio's fork. The fork also fixes a dozen functions so that 191 of the 195 functions in Foglio's compatibility audit match Excel on every test case.",
        ],
        bullets: [
          "Older `.xls`, binary `.xlsb` and LibreOffice `.ods` files are read with [calamine](https://github.com/tafia/calamine), a fast Rust reader.",
          "CSV and TSV files go through a Rust importer that detects the text encoding, the delimiter and the decimal separator.",
          "Formulas typed in Italian, German, Spanish or French are translated to Excel's standard English form before they are stored.",
        ],
      },
      {
        heading: "The bridge: a plain C interface",
        body: [
          "The Rust engine is compiled as a static library and exposes a small C interface (`foglio_core.h`): open and save a file, edit a cell, return a batch of visible cells. Swift calls it directly through a bridging header. There are no generated bindings, no frameworks and no inter-process messages, so a call into the engine costs about as much as a normal function call.",
        ],
      },
      {
        heading: "No Xcode project",
        body: [
          "Foglio is built with two commands: `cargo` builds the Rust library and `swiftc` compiles the app and links it. A shell script produces a universal app for Apple silicon and Intel and wraps it in a disk image with Apple's own `hdiutil`. You need the Xcode Command Line Tools and Rust; full Xcode is not required.",
          "Fewer layers mean fewer things to go wrong, faster builds, and a project that anyone can read from top to bottom.",
        ],
      },
      {
        heading: "Tested with real keyboard and mouse events",
        body: [
          "Foglio has 69 UI tests that drive the real app with real keyboard and mouse events: typing formulas, filling ranges, sorting, undoing, saving and reopening files. The file importers and the formula engine have their own Rust test suites, and a special mode re-checks every incremental recalculation against a full one.",
        ],
      },
      {
        heading: "Why this makes Foglio small and fast",
        body: [
          "An Electron app carries a full copy of the Chromium browser, typically well over 100 MB before it does anything. A Java or cross-platform suite carries its runtime and its own UI toolkit. Foglio carries only its own code and uses the frameworks already on every Mac.",
          "The Rust core is compiled with full link-time optimization and stripped of debug symbols. The result is a universal app of about 19 MB on disk, 7.5 MB as a compressed download, that idles at 0 % CPU.",
        ],
      },
    ],
    faq: [
      {
        q: "Is Foglio an Electron or web app?",
        a: "No. It is a native AppKit app written in Swift. There is no browser engine inside it.",
      },
      {
        q: "Does it run natively on Apple silicon?",
        a: "Yes. Foglio is a universal app with native code for both Apple silicon (arm64) and Intel (x86_64).",
      },
      {
        q: "Can I build Foglio myself?",
        a: "Yes. Install the Xcode Command Line Tools and Rust, then run `scripts/build.sh`. The [README](https://github.com/Acid236/foglio#building-from-source) has the exact commands.",
      },
      {
        q: "Are the IronCalc changes contributed upstream?",
        a: "The fork is open source under the same licenses as IronCalc, and every change is marked with a `Foglio fork:` comment and described in `third_party/README.md`, so it can be reviewed and reused.",
      },
    ],
  },

  download: {
    h1: "Download Foglio for Mac",
    intro: [
      "Foglio 1.0 is free. One universal disk image works on every Mac with macOS 14 Sonoma or later, Apple silicon and Intel alike.",
      "It is a first release: it handles everyday spreadsheets end to end, but keep backups of files that matter.",
    ],
    steps: [
      {
        title: "Download the disk image",
        text: "Click the download button to get `Foglio-1.0.dmg` (7.5 MB) from the project's GitHub releases.",
      },
      {
        title: "Drag Foglio to Applications",
        text: "Open the disk image and drag the Foglio icon onto the Applications shortcut next to it. Then eject the disk image.",
      },
      {
        title: "Open it the first time",
        text: "macOS asks for confirmation the first time because Foglio is not signed with a paid Apple Developer ID. The steps are below; you only do this once.",
      },
      {
        title: "Open your spreadsheets",
        text: "Double-click an `.xlsx` file and choose Foglio from Open With, or drag files onto the Foglio icon in the Dock.",
      },
    ],
    gatekeeperTitle: "“Unidentified developer”: how to open Foglio the first time",
    gatekeeperText: [
      "Foglio 1.0 is ad-hoc signed rather than signed and notarized with a paid Apple Developer account, so Gatekeeper cannot vouch for it and shows a warning the first time you open it. This is normal for small open-source projects, and you can read every line of the [source code](https://github.com/Acid236/foglio) or build the app yourself.",
      "**macOS 15 Sequoia or later:** double-click Foglio and close the warning. Open **System Settings ▸ Privacy & Security**, scroll down to the message about Foglio and click **Open Anyway**, then confirm with your password or Touch ID.",
      "**macOS 14 Sonoma:** in Applications, right-click (or Control-click) Foglio, choose **Open**, then click **Open** in the dialog.",
      "After that, Foglio opens normally like any other app.",
    ],
    requirementsTitle: "Requirements",
    requirements: [
      "macOS 14 Sonoma or later",
      "Apple silicon or Intel Mac (universal app)",
      "About 19 MB of disk space",
      "No account and no internet connection needed",
    ],
    sourceTitle: "Prefer to build it yourself?",
    sourceText: [
      "Foglio is open source under MIT and Apache-2.0. With the Xcode Command Line Tools and Rust installed, `scripts/build.sh` builds the same universal app from source in a few minutes, without Xcode.",
      "Release notes, older versions and the issue tracker are on [GitHub](https://github.com/Acid236/foglio/releases). Curious how it works? Read about [the technology](/technology/).",
    ],
    faq: [
      {
        q: "Is the download safe?",
        a: "The disk image is built from the public source code and published on the project's GitHub releases page. The macOS warning appears because the app is not notarized with a paid Apple account, not because anything was detected in it.",
      },
      {
        q: "How do I update Foglio?",
        a: "Foglio does not check for updates by itself, because it makes no network connections. Download the new version from this page or from GitHub releases and replace the app in Applications.",
      },
      {
        q: "How do I uninstall it?",
        a: "Drag Foglio from Applications to the Trash. Your spreadsheets are ordinary files and stay where you saved them.",
      },
      {
        q: "Can I make Foglio the default app for xlsx files?",
        a: "Yes. Select an `.xlsx` file in Finder, choose File ▸ Get Info, pick Foglio under **Open with** and click **Change All…**.",
      },
      {
        q: "Is there a version for iPhone, iPad, Windows or Linux?",
        a: "No. Foglio is a Mac app only. The engine is cross-platform Rust, but the interface is written in AppKit.",
      },
    ],
  },

  alternativesIndex: {
    h1: "Alternatives to Excel, Numbers, LibreOffice and Google Sheets",
    intro: [
      "Each of these pages explains what you gain and what you give up by moving to Foglio from a specific app, with a section on when you should keep using what you have. For step-by-step help, see the [guides](/guides/).",
    ],
  },
  guidesIndex: {
    h1: "Spreadsheet guides for Mac",
    intro: [
      "Practical answers to common Mac spreadsheet problems: opening Excel and CSV files without Excel, fixing garbled characters and wrong columns, and writing formulas in your own language. Every guide also covers the ways to do it without Foglio. Coming from another app? See the [alternatives](/alternatives/).",
    ],
  },
};
