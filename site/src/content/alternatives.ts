import type { Article, Locale } from "./types";

const UPDATED = "2026-11-09";

const en: Article[] = [
  // ───────────────────────────────────────────────────────────────────
  {
    slug: "excel-for-mac",
    meta: {
      title: "Free Excel Alternative for Mac That Opens xlsx | Foglio",
      description:
        "Need Excel on your Mac without a Microsoft 365 subscription? Foglio is a free, open-source app that opens and saves xlsx files. What it can and cannot do.",
    },
    h1: "A free Excel alternative for Mac that still opens your xlsx files",
    intro: [
      "Microsoft Excel for Mac is excellent, but it is not free. To edit spreadsheets in the desktop app you need a Microsoft 365 subscription (Personal is $99.99 a year in the US, Family $129.99) or a one-time Office Home 2024 license ($179.99 on Microsoft's store when we checked in November 2026). If you only open a budget, an invoice or a report someone emailed you a few times a month, that is a lot to pay.",
      "Foglio is a free, open-source spreadsheet app for macOS that reads and writes the same `.xlsx` files, understands about 500 Excel functions and uses Excel for Mac's keyboard shortcuts. This page explains what you keep, what you lose, and when Excel is still the right choice.",
    ],
    sections: [
      {
        heading: "What you keep when you switch",
        body: [
          "Foglio was designed to feel familiar to anyone who has used Excel. The grid, the formula bar with the Name Box, sheet tabs, the status bar sums and the menus are where you expect them. Most shortcuts are the same: ⌘1 for Format Cells, ⌘D to fill down, F4 to cycle `$` references, ⇧⌘T for AutoSum, ⌘K for a hyperlink.",
        ],
        bullets: [
          "**Your files.** `.xlsx` opens and saves with fonts, fills, borders, number formats, merged cells, column widths, frozen panes, comments, data validation, conditional formatting, hyperlinks, charts and pictures.",
          "**Your formulas.** About 500 functions, including SUMIFS, XLOOKUP, INDEX/MATCH, FILTER, SORT, UNIQUE, LET and LAMBDA. In Foglio's compatibility audit, 191 of 195 commonly used functions match Excel on every test case.",
          "**Your language.** On an Italian, German, Spanish or French Mac you type formulas with the localized names Excel uses (`=SOMMA(A1:A10)`, `=SVERWEIS(…)`), with `;` separators and decimal commas. The file stores the standard English form, so it opens in any Excel.",
          "**Your habits.** Fill handle, Paste Special, AutoFilter, multi-level sort, Find & Replace, Go To, Remove Duplicates, Text to Columns, freeze panes, Show Formulas and the Insert Function browser are all there.",
        ],
      },
      {
        heading: "What you gain",
        body: [
          "**It costs nothing, permanently.** No subscription, no trial, no account, no ads. Foglio is licensed under MIT and Apache-2.0, and the source code is on [GitHub](https://github.com/Acid236/foglio).",
          "**It is tiny and fast.** The download is 7.5 MB and the installed app is about 19 MB, against more than a gigabyte for Excel alone. Foglio opens to a usable window in 0.24 s and uses about 58 MB of memory with an empty sheet. A 100,000-row workbook with 300,000 formulas opens in 1.1 s, and after an edit it recalculates in 16 ms.",
          "**It stays on your Mac.** Foglio makes no network connections of its own and has no telemetry. You do not sign in to anything to open a file.",
        ],
      },
      {
        heading: "What you lose",
        body: [
          "Foglio 1.0 is a first release by a small project, and it does not try to be all of Excel. Before you cancel a subscription, check that your work does not depend on any of these:",
        ],
        bullets: [
          "**Macros and VBA.** `.xlsm` files open, but macros are not run and are not kept when you save.",
          "**Pivot tables.** There are no real pivot tables yet. *Summarize by* builds a live summary sheet from SUMIFS and COUNTIFS formulas, which covers simple cases.",
          "**Power Query, data connections and add-ins.** Not available.",
          "**Shapes, text boxes and SmartArt.** Skipped when a file is opened. Charts and pictures are kept.",
          "**Data bars, icon sets and sparklines.** Not drawn yet; other conditional formatting rules and color scales work.",
          "**Password-protected workbooks.** Cannot be opened.",
          "**Threaded comments** are shown as plain notes, and there is no real-time co-authoring.",
          "**Charts** cover the common types (column, bar, line, pie, doughnut, area, scatter, stacked), not Excel's full range.",
        ],
      },
      {
        heading: "Other ways to use Excel files on a Mac for free",
        body: [
          "Foglio is not the only option, and depending on your needs another one may suit you better:",
        ],
        bullets: [
          "**Excel for the web** is free with a Microsoft account and is the real Excel, in a browser. Your files live in OneDrive, and some desktop features are missing.",
          "**Apple Numbers** is free and pre-installed on many Macs. It converts `.xlsx` files to its own format and exports back to Excel when you ask.",
          "**LibreOffice Calc** is free, open source and very complete, including pivot tables and macros, but it is a large download and does not look or behave like a native Mac app.",
          "**Google Sheets** is free with a Google account and the best choice when several people edit at once.",
        ],
        sub: [
          {
            heading: "How they compare",
            body: [
              "The [full comparison table](/compare/) puts all five side by side, with sources for every price and size, and the [roundup of free spreadsheet apps](/guides/free-spreadsheet-apps-for-mac/) adds a few more. There are also dedicated pages for [Numbers](/alternatives/numbers/), [LibreOffice](/alternatives/libreoffice/) and [Google Sheets](/alternatives/google-sheets/).",
            ],
          },
        ],
      },
      {
        heading: "When you should keep Excel",
        body: [
          "Keep paying for Excel if your work runs on macros, Power Query or pivot tables, if you exchange complex models with colleagues who need everything to survive the round trip exactly, if your company requires Microsoft 365, or if you want Copilot. Excel also has iPhone, iPad and Windows versions; Foglio is Mac-only.",
          "Many people end up using both: Foglio for quick, everyday files because it opens instantly, Excel for the few heavy workbooks that need it.",
        ],
      },
      {
        heading: "How to try Foglio with your own files",
        body: [
          "[Download Foglio](/download/) (7.5 MB, macOS 14 or later), drag it to Applications and open it. Because Foglio 1.0 is not notarized by Apple, macOS asks for confirmation the first time; the download page shows how. Then open a copy of a real workbook with File ▸ Open, or right-click an `.xlsx` file and choose Open With ▸ Foglio.",
          "Check the things that matter to you: totals, lookups, dates, number formats, charts. Keep the original until you are confident. If something looks wrong, please [report it on GitHub](https://github.com/Acid236/foglio/issues) with a sample file.",
        ],
      },
    ],
    faq: [
      {
        q: "Is there a free version of Excel for Mac?",
        a: "The desktop app needs a Microsoft 365 subscription or an Office license to create and edit files. Excel for the web is free with a Microsoft account. Free desktop alternatives that open Excel files include Foglio, LibreOffice Calc and Apple Numbers.",
      },
      {
        q: "Will a file saved by Foglio open correctly in Excel?",
        a: "Yes, Foglio saves standard `.xlsx` files with formulas in Excel's English form. Formatting, charts, pictures, comments, validation and conditional formatting are written back. Features Foglio does not support, such as macros, shapes or pivot tables, are not preserved, so keep the original of complex files.",
      },
      {
        q: "Does Foglio use the same keyboard shortcuts as Excel for Mac?",
        a: "Mostly, yes: ⌘1 Format Cells, ⌘D / ⌘R fill, F4 absolute references, ⇧⌘T AutoSum, ⌥⇧⌘V paste values, ⌃; insert date, ⌥↓ open a validation list, and many more. The README on GitHub has the full list.",
      },
      {
        q: "Is Foglio as fast as Excel on big files?",
        a: "We have not benchmarked Excel, so we will not claim to beat it. On our test Mac, Foglio opens a 100,000-row workbook with 300,000 formulas in 1.1 s and recalculates after an edit in 16 ms, which feels instant.",
      },
      {
        q: "Can I use Foglio for work?",
        a: "Yes. The MIT and Apache-2.0 licenses allow commercial use at no cost. As with any 1.0 software, keep backups of important files.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Free Excel alternative for Mac",
    cardText: "Open and save xlsx files without a Microsoft 365 subscription, and know exactly what you give up.",
  },

  // ───────────────────────────────────────────────────────────────────
  {
    slug: "numbers",
    meta: {
      title: "Numbers Alternative That Edits Excel Files | Foglio",
      description:
        "Numbers converts Excel files to its own format. Foglio is a free Mac app that edits xlsx directly with Excel formulas and shortcuts. When each one fits.",
    },
    h1: "A Numbers alternative that works with Excel files as they are",
    intro: [
      "Apple Numbers is a good app. It is free, it is beautifully designed and it syncs with your iPhone and iPad. But it is built around its own idea of a spreadsheet: a free-form canvas with tables placed on it, saved as `.numbers`. When someone sends you an Excel file, Numbers imports it, converts it, and you have to remember to export it back to Excel before sending it on.",
      "Foglio takes the opposite approach. It is a free, open-source Mac app that works on `.xlsx` files directly, with Excel's grid, Excel's function names and Excel for Mac's shortcuts. If your spreadsheets come from, and go back to, Excel users, that difference matters every day.",
    ],
    sections: [
      {
        heading: "Why Excel users find Numbers awkward",
        body: [
          "None of these are bugs; they are design choices. They just happen to get in the way when you work with Excel files.",
        ],
        bullets: [
          "**Import and export instead of open and save.** An `.xlsx` opened in Numbers becomes a Numbers document. Saving creates a `.numbers` file; you must use File ▸ Export To ▸ Excel to send it back, and some things change on the way.",
          "**Tables on a canvas, not one big grid.** A Numbers sheet holds several separate tables, so large Excel sheets can be split or reshaped on import.",
          "**Different shortcuts and menus.** Many Excel for Mac shortcuts do nothing or something else in Numbers.",
          "**Newer system requirement.** The current Numbers on the App Store requires macOS 26; Foglio runs on macOS 14 and later.",
        ],
      },
      {
        heading: "What Foglio does differently",
        bullets: [
          "**It edits `.xlsx` in place.** Open an Excel file, change it, press ⌘S, and it is still an Excel file. No export step.",
          "**One grid per sheet, like Excel.** Row and column headers, freeze panes, the Name Box (type `B12` or `Sheet2!A1:C9` to jump), sheet tabs you can rename, color, hide and reorder.",
          "**Excel's formulas and Excel's names.** About 500 functions, including XLOOKUP, SUMIFS, FILTER, LET and LAMBDA, typed in your Mac's language: `=SOMMA(A1:A10)` on an Italian Mac, `=SUMME(…)` on a German one ([Italian–English list](/guides/excel-functions-italian-english/)).",
          "**Excel for Mac shortcuts.** ⌘1, ⌘D, F4, ⇧⌘T, ⌥⇧⌘V and dozens more behave as in Excel.",
          "**Files Numbers struggles with.** Foglio opens old `.xls`, binary `.xlsb` and LibreOffice `.ods` files, and CSV files in any common encoding with automatic delimiter detection. It even draws old EMF/WMF clip art inside Office files.",
        ],
        body: [],
      },
      {
        heading: "What Numbers does better",
        body: [
          "Be honest with yourself about what you use Numbers for. If it is any of the following, Numbers may still be the better tool:",
        ],
        bullets: [
          "**Presentation.** Templates, styled tables, interactive charts and free layout make Numbers documents look great without effort.",
          "**iPhone and iPad.** Numbers runs on all your Apple devices and syncs through iCloud. Foglio is Mac-only.",
          "**Collaboration.** Numbers supports real-time collaboration through iCloud. Foglio is a single-user desktop app.",
          "**Pivot tables.** Numbers has them; Foglio offers only *Summarize by*, a simpler live summary.",
          "**Apple Intelligence.** Numbers integrates Writing Tools and, with an Apple Creator Studio subscription, an assistant that can suggest formulas and tables. Foglio has no AI features.",
        ],
      },
      {
        heading: "Size and speed",
        body: [
          "The Numbers App Store listing shows 661 MB (a single listing for Mac, iPhone and iPad). Foglio is a 7.5 MB download and about 19 MB installed. It opens to a usable window in 0.24 s, idles at 0 % CPU and uses about 58 MB of memory with an empty sheet. A 100,000-row workbook with 300,000 formulas opens in 1.1 s on our test Mac.",
          "Numbers is pre-installed on many Macs, so size may not matter to you. Startup time and how it handles very large Excel sheets might.",
        ],
      },
      {
        heading: "When you should stay with Numbers",
        body: [
          "If your spreadsheets are personal, rarely leave your Apple devices, and you value how they look more than Excel compatibility, stay with Numbers. It is free, polished and well integrated. If you share a household budget with family members on iPhones, Numbers' iCloud collaboration is hard to beat.",
          "If instead you regularly open Excel attachments, send `.xlsx` files back to colleagues or clients, or simply think in Excel, Foglio removes the conversion step. Plenty of people keep both: Numbers for pretty personal documents, Foglio as the default app for `.xlsx` and `.csv`.",
        ],
      },
      {
        heading: "Make Foglio the default for Excel files",
        body: [
          "After you [download Foglio](/download/), select any `.xlsx` file in Finder, press ⌘I (Get Info), choose Foglio under **Open with** and click **Change All…**. Double-clicking Excel files will now open them in Foglio, and Numbers stays available for its own documents. Repeat for `.csv` if you like.",
          "For a broader look at every option, see the [comparison of Mac spreadsheet apps](/compare/) or the guide on [opening xlsx files without Excel](/guides/open-xlsx-on-mac-without-excel/).",
        ],
      },
    ],
    faq: [
      {
        q: "Can Foglio open .numbers files?",
        a: "No. Foglio does not read Apple's `.numbers` format. In Numbers, use File ▸ Export To ▸ Excel to create an `.xlsx` that Foglio can open.",
      },
      {
        q: "Is Foglio free like Numbers?",
        a: "Yes. Foglio is free with no paid tier at all, and it is also open source under MIT and Apache-2.0.",
      },
      {
        q: "Does Numbers keep my Excel formulas?",
        a: "Numbers translates most common formulas on import and back on export, but functions it lacks, Excel-specific features and layout can change. Foglio keeps the workbook in Excel format throughout.",
      },
      {
        q: "Will Foglio run on my older Mac?",
        a: "Foglio needs macOS 14 Sonoma or later, on Apple silicon or Intel. The current version of Numbers requires macOS 26.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Numbers alternative for Excel files",
    cardText: "Edit xlsx files in place, with Excel's grid, function names and shortcuts, instead of converting them.",
  },

  // ───────────────────────────────────────────────────────────────────
  {
    slug: "libreoffice",
    meta: {
      title: "Lightweight LibreOffice Calc Alternative for Mac | Foglio",
      description:
        "LibreOffice is free but large and not a native Mac app. Foglio is a 7.5 MB open-source spreadsheet in Swift and Rust. Honest notes on when to use which.",
    },
    h1: "A lightweight, native alternative to LibreOffice Calc on the Mac",
    intro: [
      "LibreOffice is one of the great free-software projects: a complete office suite, free for everyone, with a spreadsheet (Calc) that has pivot tables, macros, a huge function library and support for almost every file format. If you want a free Excel replacement, it is the obvious first suggestion.",
      "On a Mac, though, it shows its cross-platform roots. The Apple silicon disk image is about 300 MB, it installs a whole suite even if you only want spreadsheets, and its interface, dialogs and shortcuts do not quite feel like the rest of macOS. Foglio is a different trade-off: much smaller, native, and focused only on spreadsheets.",
    ],
    sections: [
      {
        heading: "Two free, open-source apps with different goals",
        body: [
          "Both apps are free and open source, and both work completely offline with no account and no telemetry. The difference is scope. LibreOffice aims to be a complete alternative to Microsoft Office on every desktop platform. Foglio aims to be the fastest, lightest way to open and edit everyday Excel spreadsheets on a Mac, and nothing else.",
        ],
        bullets: [
          "**Foglio:** Swift/AppKit interface, Rust engine, Mac only, MIT / Apache-2.0, 7.5 MB download, about 19 MB installed.",
          "**LibreOffice:** C++ suite with its own UI toolkit, Windows, macOS and Linux, MPL-2.0, about 300 MB download, up to 800 MB on disk according to its system requirements.",
        ],
      },
      {
        heading: "Where Foglio is better",
        bullets: [
          "**Size and startup.** Foglio opens to a usable window in 0.24 s and uses about 58 MB of memory with an empty sheet, with 0 % CPU when idle.",
          "**A native Mac app.** Real macOS documents, window tabs, dark mode, standard Open and Save panels, pinch to zoom, smooth scrolling on a custom grid, and Excel for Mac keyboard shortcuts.",
          "**Excel's way of doing things.** `.xlsx` is Foglio's own format, not an import filter. Function names follow Excel in your language (`CERCA.VERT`, `SVERWEIS`, `BUSCARV`).",
          "**Modern Excel functions.** Foglio supports LAMBDA as well as XLOOKUP, FILTER, SORT and LET. LibreOffice added XLOOKUP, FILTER and LET in 2024 but, at the time of writing, does not implement LAMBDA.",
          "**Speed on big workbooks.** Thanks to incremental recalculation and indexed lookups, an edit in a 100,000-row workbook with 300,000 formulas recalculates in 16 ms on our test Mac.",
        ],
        body: [],
      },
      {
        heading: "Where LibreOffice Calc is better",
        body: [
          "LibreOffice has decades of development behind it, and for many tasks it is simply more capable:",
        ],
        bullets: [
          "**Pivot tables** (with calculated fields in recent versions). Foglio offers only *Summarize by*.",
          "**Macros** in LibreOffice Basic and Python, with partial support for Excel VBA. Foglio runs no macros.",
          "**More chart types**, shapes, drawing tools and text boxes.",
          "**Saving in more formats**, including `.ods`, `.xls` and many others. Foglio opens `.xls` and `.ods` (values, formulas and dates) but saves only `.xlsx`, CSV and PDF.",
          "**Password-protected files**, data bars, icon sets and sparklines, which Foglio does not support yet.",
          "**A whole suite**: Writer, Impress, Draw and Base come in the same download.",
          "**Windows and Linux** versions, if you work across platforms.",
        ],
      },
      {
        heading: "When you should keep LibreOffice",
        body: [
          "Keep LibreOffice if you need pivot tables or macros, work with OpenDocument as your main format, need a word processor and presentations too, or use the same suite on Windows or Linux. It is a mature, trustworthy project, and it costs nothing to keep it installed.",
          "Choose Foglio if what you actually do is open spreadsheets people send you, fix a few numbers and send them back, and you want an app that starts instantly, feels like the rest of your Mac and does not use 800 MB of disk to do it. The two can live side by side: make Foglio the default for `.xlsx` and `.csv`, and open LibreOffice for the jobs that need it.",
        ],
      },
      {
        heading: "Switching is easy because the files are the same",
        body: [
          "There is no migration. Both apps read and write `.xlsx`, so a file edited in one opens in the other. If you have `.ods` files, Foglio opens their values, formulas and dates and saves them as `.xlsx`; formatting from `.ods` files is not carried over yet, so keep the originals. The same applies to old `.xls` files; see [how to open .xls files on a Mac](/guides/open-xls-on-mac/).",
          "[Download Foglio](/download/), try it on a few real files, and check the [comparison table](/compare/) for the details. If you are curious why it is so small, read [how Foglio is built](/technology/).",
        ],
      },
    ],
    faq: [
      {
        q: "Is Foglio based on LibreOffice?",
        a: "No. Foglio is a separate project. Its interface is written in Swift/AppKit, and its formula engine is a patched fork of IronCalc, an open-source spreadsheet engine in Rust. It uses the calamine Rust library to read `.xls`, `.xlsb` and `.ods`.",
      },
      {
        q: "Are both free for commercial use?",
        a: "Yes. LibreOffice is under the MPL-2.0 and Foglio under MIT and Apache-2.0. Both can be used at work at no cost.",
      },
      {
        q: "Which one opens Excel files better?",
        a: "It depends on the file. LibreOffice supports more Excel features overall (pivot tables, macros, shapes). Foglio treats `.xlsx` as its native format and matches Excel's results on 191 of 195 audited functions. Try your own files in both.",
      },
      {
        q: "Does Foglio save .ods files?",
        a: "No. Foglio opens `.ods` and saves as `.xlsx`. If you need to keep OpenDocument files, use LibreOffice.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Lighter LibreOffice Calc alternative",
    cardText: "A native 7.5 MB Mac spreadsheet for everyday Excel files, and when LibreOffice is still the better tool.",
  },

  // ───────────────────────────────────────────────────────────────────
  {
    slug: "google-sheets",
    meta: {
      title: "Offline Google Sheets Alternative for Mac | Foglio",
      description:
        "Want spreadsheets that work offline and stay on your Mac? Foglio is a free, private desktop app with no account. When Google Sheets is still better.",
    },
    h1: "An offline, private alternative to Google Sheets for Mac",
    intro: [
      "Google Sheets is free, capable and unbeatable when several people need to edit the same sheet at once. It also comes with conditions: you need a Google account, your files live on Google's servers, it runs in a browser tab, and working offline needs Chrome or Edge, an extension and some setup done in advance.",
      "Foglio is a free, open-source spreadsheet app that runs entirely on your Mac. No account, no sign-in, no network connections of its own. Your files are ordinary `.xlsx` files in a folder you choose. Here is how the two compare, honestly.",
    ],
    sections: [
      {
        heading: "Why people look for a Google Sheets alternative",
        bullets: [
          "**Offline work.** On a plane, a train or a weak hotel connection, a desktop app simply works. Google's offline mode must be enabled while online, needs the Google Docs Offline extension in Chrome or Edge, and only one account per browser profile can use it.",
          "**Privacy.** Some data should not be uploaded anywhere: payroll, medical expenses, client lists. With Foglio, the file never leaves your Mac unless you send it.",
          "**No account.** Not everyone has, or wants, a Google account, and some workplaces do not allow personal cloud storage.",
          "**A real Mac app.** A browser tab is not a Mac app: no Open Recent, no window tabs of their own, no native print dialog, no Mac shortcuts. Foglio is written in Swift/AppKit.",
          "**Big local files.** Opening a large `.xlsx` in Sheets means uploading and converting it, and Google sets a limit of 20 million cells per spreadsheet. Foglio opens a 100,000-row, 300,000-formula workbook in 1.1 s on our test Mac.",
        ],
        body: [],
      },
      {
        heading: "What you keep from Google Sheets",
        body: [
          "Most of what you do in Sheets works the same way in Foglio. Formulas use the same Excel-style syntax and function names: SUMIFS, XLOOKUP, FILTER, SORT, UNIQUE, LET and LAMBDA are all there, among about 500 functions. AutoFilter, sorting, data validation dropdowns, conditional formatting with color scales, charts, find and replace, freeze panes and comments are all supported.",
          "To bring a sheet over, use File ▸ Download ▸ Microsoft Excel (.xlsx) in Google Sheets and open the file in Foglio. Formatting, formulas and charts come across; Google-only functions such as GOOGLEFINANCE, IMPORTRANGE or QUERY have no equivalent in Foglio or Excel.",
        ],
      },
      {
        heading: "What Google Sheets does better",
        bullets: [
          "**Real-time collaboration.** Several cursors in one sheet, comments with mentions, version history. Foglio is a single-user desktop app.",
          "**Every device.** Sheets runs in any browser and has iPhone, iPad and Android apps. Foglio runs only on Macs with macOS 14 or later.",
          "**Online data.** Functions like IMPORTRANGE, IMPORTHTML and GOOGLEFINANCE pull live data from the web. Foglio does not connect to the internet.",
          "**Automation and AI.** Apps Script for automation and, depending on your plan, Gemini for help with formulas and analysis. Foglio has neither macros nor AI features.",
          "**Pivot tables and more chart types.** Foglio offers *Summarize by* for simple summaries and the common chart types.",
        ],
        body: [],
      },
      {
        heading: "When you should keep using Google Sheets",
        body: [
          "If your spreadsheet is a shared space, such as a team tracker, a family packing list or a sign-up sheet, Google Sheets is the right tool and Foglio is not trying to replace it. The same goes for sheets that pull live data from the web, or that you need to edit from a phone.",
          "If the sheet is yours, local, or confidential, a desktop app makes more sense. Many people use both: Google Sheets for shared documents, Foglio for personal finances, client data and the Excel files that arrive by email.",
        ],
      },
      {
        heading: "Your files, your folder",
        body: [
          "Foglio saves standard `.xlsx` files wherever you like: your Documents folder, an external drive, or a synced folder such as iCloud Drive or Dropbox if you choose. Because they are Excel files, you can always upload one to Google Sheets later. There is no lock-in in either direction.",
          "[Download Foglio](/download/) for free (7.5 MB, macOS 14+). To see how it stacks up against Excel, Numbers and LibreOffice as well, read the [full comparison](/compare/).",
        ],
      },
    ],
    faq: [
      {
        q: "Can Google Sheets work offline on a Mac?",
        a: "Yes, with limits: you need Chrome or Microsoft Edge, the Google Docs Offline extension, and you must turn offline access on while connected. Only one account per browser profile can use it. A desktop app like Foglio, Numbers, LibreOffice or Excel works offline without setup.",
      },
      {
        q: "Does Foglio upload my files anywhere?",
        a: "No. Foglio has no account system, no cloud storage and no telemetry, and it makes no network connections of its own. It opens a web page only when you click a hyperlink in a cell.",
      },
      {
        q: "Can I open a Google Sheets file in Foglio?",
        a: "Download it first with File ▸ Download ▸ Microsoft Excel (.xlsx) in Google Sheets, then open the `.xlsx` in Foglio. A `.gsheet` shortcut file from Google Drive for desktop is only a link and cannot be opened offline.",
      },
      {
        q: "Will my Google Sheets formulas work in Foglio?",
        a: "Standard formulas will, since both follow Excel's syntax. Google-specific functions such as QUERY, IMPORTRANGE, GOOGLEFINANCE and SPARKLINE are not available in Foglio.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Offline Google Sheets alternative",
    cardText: "A free desktop spreadsheet with no account and no cloud, and when Google Sheets is still the right tool.",
  },
];

const it: Article[] = [
  // ───────────────────────────────────────────────────────────────────
  {
    slug: "excel-for-mac",
    meta: {
      title: "Alternativa gratuita a Excel per Mac | Foglio",
      description:
        "Vuoi Excel sul Mac senza abbonamento a Microsoft 365? Foglio è un'app gratuita e open source che apre e salva i file xlsx. Cosa sa fare e cosa no.",
    },
    h1: "Un'alternativa gratuita a Excel per Mac che apre i tuoi file xlsx",
    intro: [
      "Microsoft Excel per Mac è ottimo, ma non è gratis. Per modificare i fogli nell'app desktop serve un abbonamento a Microsoft 365 (in Italia Personal costa 99 € all'anno, Family 129 €) oppure una licenza a vita di Office Home 2024 (149 € sullo store Microsoft a novembre 2026). Se ti capita di aprire un bilancio, una fattura o un report ricevuto per email qualche volta al mese, è una spesa importante.",
      "Foglio è un'app per fogli di calcolo gratuita e open source per macOS: legge e scrive gli stessi file `.xlsx`, conosce circa 500 funzioni di Excel, accetta le formule in italiano e usa le scorciatoie da tastiera di Excel per Mac. Questa pagina spiega cosa mantieni, cosa perdi e quando Excel resta la scelta giusta.",
    ],
    sections: [
      {
        heading: "Cosa mantieni passando a Foglio",
        body: [
          "Foglio è pensato per risultare familiare a chiunque abbia usato Excel. La griglia, la barra della formula con la Casella Nome, le schede dei fogli, la somma nella barra di stato e i menu sono dove te li aspetti. Le scorciatoie sono quasi tutte le stesse: ⌘1 per Formato celle, ⌘D per riempire in basso, F4 per i riferimenti assoluti con `$`, ⇧⌘T per la Somma automatica, ⌘K per un collegamento.",
        ],
        bullets: [
          "**I tuoi file.** Gli `.xlsx` si aprono e si salvano con caratteri, riempimenti, bordi, formati numerici, celle unite, larghezze delle colonne, riquadri bloccati, note, convalida dati, formattazione condizionale, collegamenti, grafici e immagini.",
          "**Le tue formule.** Circa 500 funzioni, tra cui SOMMA.PIÙ.SE, CERCA.X, INDICE/CONFRONTA, FILTRO, ORDINA, LET e LAMBDA. Nella verifica di compatibilità di Foglio, 191 delle 195 funzioni più usate danno gli stessi risultati di Excel in ogni caso di prova.",
          "**La tua lingua.** Su un Mac in italiano scrivi `=SOMMA(A1:A10;B2)`, `SE`, `CERCA.VERT` con il punto e virgola e la virgola decimale, come in Excel in italiano. Nel file la formula viene salvata nella forma standard inglese, quindi si apre in qualsiasi Excel del mondo.",
          "**Le tue abitudini.** Quadratino di riempimento, Incolla speciale, Filtro automatico, ordinamento su più livelli, Trova e sostituisci, Vai a, Rimuovi duplicati, Testo in colonne, Blocca riquadri, Mostra formule e la finestra Inserisci funzione ci sono tutti.",
        ],
      },
      {
        heading: "Cosa guadagni",
        body: [
          "**Non costa nulla, per sempre.** Nessun abbonamento, nessuna prova, nessun account, nessuna pubblicità. Foglio è distribuito con licenza MIT e Apache-2.0 e il codice sorgente è su [GitHub](https://github.com/Acid236/foglio).",
          "**È piccolissimo e veloce.** Il download pesa 7,5 MB e l'app installata circa 19 MB, contro oltre un gigabyte del solo Excel. Foglio mostra una finestra pronta in 0,24 s e usa circa 58 MB di memoria con un foglio vuoto. Una cartella da 100.000 righe e 300.000 formule si apre in 1,1 s e dopo una modifica si ricalcola in 16 ms.",
          "**Resta sul tuo Mac.** Foglio non apre connessioni di rete di sua iniziativa e non ha telemetria. Per aprire un file non devi accedere a nessun servizio.",
        ],
      },
      {
        heading: "Cosa perdi",
        body: [
          "Foglio 1.0 è la prima versione di un piccolo progetto e non cerca di essere tutto Excel. Prima di disdire un abbonamento, verifica che il tuo lavoro non dipenda da nessuno di questi punti:",
        ],
        bullets: [
          "**Macro e VBA.** I file `.xlsm` si aprono, ma le macro non vengono eseguite né conservate al salvataggio.",
          "**Tabelle pivot.** Non ci sono ancora vere tabelle pivot. *Riepiloga per* crea un foglio di riepilogo aggiornato automaticamente con formule SOMMA.PIÙ.SE e CONTA.PIÙ.SE, che basta per i casi semplici.",
          "**Power Query, connessioni dati e componenti aggiuntivi.** Non disponibili.",
          "**Forme, caselle di testo e SmartArt.** Vengono ignorate all'apertura del file. Grafici e immagini invece restano.",
          "**Barre dei dati, set di icone e grafici sparkline.** Non ancora disegnati; le altre regole di formattazione condizionale e le scale di colori funzionano.",
          "**Cartelle protette da password.** Non si possono aprire.",
          "**Commenti in thread** mostrati come semplici note, e niente modifica in contemporanea con altre persone.",
          "**Grafici** limitati ai tipi più comuni (colonne, barre, linee, torta, anello, area, dispersione, in pila), non tutta la gamma di Excel.",
        ],
      },
      {
        heading: "Altri modi per usare i file Excel gratis sul Mac",
        body: ["Foglio non è l'unica possibilità, e a seconda delle tue esigenze un'altra soluzione potrebbe andarti meglio:"],
        bullets: [
          "**Excel per il web** è gratuito con un account Microsoft ed è il vero Excel, nel browser. I file stanno su OneDrive e mancano alcune funzioni della versione desktop.",
          "**Apple Numbers** è gratuito e già installato su molti Mac. Converte i file `.xlsx` nel proprio formato e li esporta di nuovo in Excel quando glielo chiedi.",
          "**LibreOffice Calc** è gratuito, open source e completissimo, tabelle pivot e macro comprese, ma è un download pesante e non ha l'aspetto né il comportamento di un'app Mac nativa.",
          "**Fogli Google** è gratuito con un account Google ed è la scelta migliore quando più persone lavorano sullo stesso foglio.",
        ],
        sub: [
          {
            heading: "Come si confrontano",
            body: [
              "La [tabella di confronto completa](/compare/) mette le cinque app una accanto all'altra, con le fonti di ogni prezzo e dimensione, e la [rassegna dei fogli di calcolo gratis](/guides/free-spreadsheet-apps-for-mac/) aggiunge altre opzioni. Ci sono anche pagine dedicate a [Numbers](/alternatives/numbers/), [LibreOffice](/alternatives/libreoffice/) e [Fogli Google](/alternatives/google-sheets/).",
            ],
          },
        ],
      },
      {
        heading: "Quando conviene tenersi Excel",
        body: [
          "Continua a pagare Excel se il tuo lavoro si basa su macro, Power Query o tabelle pivot, se scambi modelli complessi con colleghi che devono ritrovare tutto identico, se la tua azienda richiede Microsoft 365, o se vuoi Copilot. Excel esiste anche per iPhone, iPad e Windows; Foglio solo per Mac.",
          "Molti finiscono per usarli entrambi: Foglio per i file di tutti i giorni, perché si apre all'istante, ed Excel per le poche cartelle pesanti che ne hanno davvero bisogno.",
        ],
      },
      {
        heading: "Come provare Foglio con i tuoi file",
        body: [
          "[Scarica Foglio](/download/) (7,5 MB, macOS 14 o successivo), trascinalo in Applicazioni e aprilo. Poiché Foglio 1.0 non è notarizzato da Apple, la prima volta macOS chiede conferma: la pagina di download spiega come fare. Poi apri una copia di una cartella di lavoro reale con Archivio ▸ Apri, oppure fai clic destro su un file `.xlsx` e scegli Apri con ▸ Foglio.",
          "Controlla le cose che contano per te: totali, ricerche, date, formati numerici, grafici. Conserva l'originale finché non sei sicuro. Se qualcosa non torna, [segnalalo su GitHub](https://github.com/Acid236/foglio/issues) allegando un file di esempio.",
        ],
      },
    ],
    faq: [
      {
        q: "Esiste una versione gratuita di Excel per Mac?",
        a: "L'app desktop richiede un abbonamento a Microsoft 365 o una licenza di Office per creare e modificare file. Excel per il web è gratuito con un account Microsoft. Tra le alternative desktop gratuite che aprono i file Excel ci sono Foglio, LibreOffice Calc e Apple Numbers.",
      },
      {
        q: "Un file salvato con Foglio si apre correttamente in Excel?",
        a: "Sì: Foglio salva normali file `.xlsx`, con le formule nella forma inglese standard di Excel. Formattazione, grafici, immagini, note, convalida e formattazione condizionale vengono riscritti. Ciò che Foglio non supporta, come macro, forme o tabelle pivot, non viene conservato: tieni l'originale dei file complessi.",
      },
      {
        q: "Foglio usa le stesse scorciatoie di Excel per Mac?",
        a: "Quasi tutte: ⌘1 Formato celle, ⌘D / ⌘R per riempire, F4 per i riferimenti assoluti, ⇧⌘T Somma automatica, ⌥⇧⌘V incolla valori, ⌃; inserisce la data, ⌥↓ apre un elenco di convalida, e molte altre. Il README su GitHub ha l'elenco completo.",
      },
      {
        q: "Posso usare Foglio per lavoro?",
        a: "Sì. Le licenze MIT e Apache-2.0 consentono l'uso commerciale senza costi. Come per qualsiasi software alla versione 1.0, tieni un backup dei file importanti.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Alternativa gratuita a Excel per Mac",
    cardText: "Apri e salva file xlsx senza abbonamento a Microsoft 365, sapendo esattamente a cosa rinunci.",
  },

  // ───────────────────────────────────────────────────────────────────
  {
    slug: "numbers",
    meta: {
      title: "Alternativa a Numbers che modifica i file Excel | Foglio",
      description:
        "Numbers converte i file Excel nel suo formato. Foglio è un'app Mac gratuita che modifica gli xlsx direttamente, con formule e scorciatoie di Excel.",
    },
    h1: "Un'alternativa a Numbers che lavora sui file Excel così come sono",
    intro: [
      "Apple Numbers è una buona app: gratuita, curata nel design e sincronizzata con iPhone e iPad. Però è costruita attorno alla propria idea di foglio di calcolo, una tela libera su cui si posizionano tabelle, salvata in formato `.numbers`. Quando qualcuno ti manda un file Excel, Numbers lo importa, lo converte e devi ricordarti di esportarlo di nuovo in Excel prima di rimandarlo.",
      "Foglio fa l'opposto. È un'app Mac gratuita e open source che lavora direttamente sui file `.xlsx`, con la griglia di Excel, i nomi delle funzioni di Excel in italiano e le scorciatoie di Excel per Mac. Se i tuoi fogli arrivano da utenti Excel e a loro tornano, la differenza si sente ogni giorno.",
    ],
    sections: [
      {
        heading: "Perché chi usa Excel trova Numbers scomodo",
        body: ["Non sono difetti, ma scelte di progetto. Solo che intralciano quando lavori con file Excel."],
        bullets: [
          "**Importa ed esporta, invece di aprire e salvare.** Un `.xlsx` aperto in Numbers diventa un documento Numbers. Salvando ottieni un file `.numbers`; per rimandarlo devi usare Archivio ▸ Esporta come ▸ Excel, e lungo la strada qualcosa cambia.",
          "**Tabelle su una tela, non un'unica griglia.** Un foglio di Numbers contiene più tabelle separate, quindi i fogli Excel grandi possono essere divisi o rimodellati all'importazione.",
          "**Scorciatoie e menu diversi.** Molte scorciatoie di Excel per Mac in Numbers non fanno nulla, o fanno altro.",
          "**Requisiti di sistema più recenti.** La versione attuale di Numbers sull'App Store richiede macOS 26; Foglio funziona da macOS 14 in poi.",
        ],
      },
      {
        heading: "Cosa fa Foglio di diverso",
        body: [],
        bullets: [
          "**Modifica gli `.xlsx` direttamente.** Apri un file Excel, lo modifichi, premi ⌘S ed è ancora un file Excel. Nessuna esportazione.",
          "**Una griglia per foglio, come in Excel.** Intestazioni di righe e colonne, riquadri bloccati, Casella Nome (scrivi `B12` o `Foglio2!A1:C9` per spostarti), schede dei fogli da rinominare, colorare, nascondere e riordinare.",
          "**Le formule e i nomi di Excel.** Circa 500 funzioni, tra cui CERCA.X, SOMMA.PIÙ.SE, FILTRO, LET e LAMBDA, scritte in italiano con il punto e virgola: `=SOMMA(A1:A10;B2)` (vedi la [tabella italiano–inglese](/guides/excel-functions-italian-english/)).",
          "**Le scorciatoie di Excel per Mac.** ⌘1, ⌘D, F4, ⇧⌘T, ⌥⇧⌘V e decine di altre funzionano come in Excel.",
          "**I file su cui Numbers inciampa.** Foglio apre i vecchi `.xls`, i binari `.xlsb`, gli `.ods` di LibreOffice e i CSV in qualsiasi codifica comune, con riconoscimento automatico del separatore. Disegna perfino le vecchie clip art EMF/WMF dentro i file Office.",
        ],
      },
      {
        heading: "Cosa fa meglio Numbers",
        body: ["Chiediti con sincerità per cosa usi Numbers. Se è per uno di questi motivi, Numbers potrebbe restare lo strumento migliore:"],
        bullets: [
          "**L'aspetto.** Modelli, tabelle con stile, grafici interattivi e impaginazione libera rendono belli i documenti senza fatica.",
          "**iPhone e iPad.** Numbers funziona su tutti i tuoi dispositivi Apple e si sincronizza con iCloud. Foglio esiste solo per Mac.",
          "**Collaborazione.** Numbers permette di lavorare insieme in tempo reale tramite iCloud. Foglio è un'app desktop per una persona alla volta.",
          "**Tabelle pivot.** Numbers le ha; Foglio offre solo *Riepiloga per*, un riepilogo dinamico più semplice.",
          "**Apple Intelligence.** Numbers integra gli Strumenti di scrittura e, con un abbonamento ad Apple Creator Studio, un assistente che suggerisce formule e tabelle. Foglio non ha funzioni di intelligenza artificiale.",
        ],
      },
      {
        heading: "Dimensioni e velocità",
        body: [
          "La scheda di Numbers sull'App Store indica 661 MB (un'unica scheda per Mac, iPhone e iPad). Foglio pesa 7,5 MB da scaricare e circa 19 MB installato. Mostra una finestra pronta in 0,24 s, a riposo usa lo 0 % della CPU e circa 58 MB di memoria con un foglio vuoto. Sul nostro Mac di prova una cartella da 100.000 righe e 300.000 formule si apre in 1,1 s.",
          "Numbers è già installato su molti Mac, quindi lo spazio potrebbe non interessarti. I tempi di avvio e il comportamento con fogli Excel molto grandi, forse sì.",
        ],
      },
      {
        heading: "Quando conviene restare con Numbers",
        body: [
          "Se i tuoi fogli sono personali, raramente escono dai tuoi dispositivi Apple e per te conta più l'aspetto della compatibilità con Excel, resta con Numbers: è gratuito, rifinito e ben integrato. Se condividi il bilancio di casa con la famiglia su iPhone, la collaborazione via iCloud di Numbers è difficile da battere.",
          "Se invece apri spesso allegati Excel, rimandi file `.xlsx` a colleghi o clienti, o semplicemente ragioni in Excel, Foglio elimina il passaggio di conversione. Molti tengono entrambi: Numbers per i documenti personali curati, Foglio come app predefinita per `.xlsx` e `.csv`.",
        ],
      },
      {
        heading: "Imposta Foglio come app predefinita per i file Excel",
        body: [
          "Dopo aver [scaricato Foglio](/download/), seleziona un file `.xlsx` nel Finder, premi ⌘I (Ottieni informazioni), scegli Foglio in **Apri con** e fai clic su **Modifica tutto…**. Da quel momento il doppio clic sui file Excel li apre in Foglio, mentre Numbers resta disponibile per i suoi documenti. Se vuoi, ripeti per i `.csv`.",
          "Per un quadro completo di tutte le opzioni, leggi il [confronto tra fogli di calcolo per Mac](/compare/) o la guida su come [aprire file xlsx su Mac senza Excel](/guides/open-xlsx-on-mac-without-excel/).",
        ],
      },
    ],
    faq: [
      {
        q: "Foglio apre i file .numbers?",
        a: "No. Foglio non legge il formato `.numbers` di Apple. In Numbers usa Archivio ▸ Esporta come ▸ Excel per creare un `.xlsx` che Foglio può aprire.",
      },
      {
        q: "Foglio è gratis come Numbers?",
        a: "Sì. Foglio è gratuito e non ha alcuna versione a pagamento; in più è open source con licenza MIT e Apache-2.0.",
      },
      {
        q: "Numbers conserva le mie formule di Excel?",
        a: "Numbers traduce la maggior parte delle formule comuni all'importazione e all'esportazione, ma le funzioni che non ha, le caratteristiche specifiche di Excel e l'impaginazione possono cambiare. Foglio mantiene la cartella in formato Excel dall'inizio alla fine.",
      },
      {
        q: "Foglio funziona sul mio Mac meno recente?",
        a: "Foglio richiede macOS 14 Sonoma o successivo, su Apple silicon o Intel. La versione attuale di Numbers richiede macOS 26.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Alternativa a Numbers per i file Excel",
    cardText: "Modifica gli xlsx senza convertirli, con la griglia, i nomi delle funzioni e le scorciatoie di Excel.",
  },

  // ───────────────────────────────────────────────────────────────────
  {
    slug: "libreoffice",
    meta: {
      title: "Alternativa leggera a LibreOffice Calc per Mac | Foglio",
      description:
        "LibreOffice è gratis ma pesante e non nativo su Mac. Foglio è un foglio di calcolo open source da 7,5 MB in Swift e Rust. Quando usare l'uno o l'altro.",
    },
    h1: "Un'alternativa leggera e nativa a LibreOffice Calc sul Mac",
    intro: [
      "LibreOffice è uno dei grandi progetti di software libero: una suite per ufficio completa, gratuita per tutti, con un foglio di calcolo (Calc) che ha tabelle pivot, macro, una libreria di funzioni enorme e il supporto a quasi ogni formato di file. Se cerchi un sostituto gratuito di Excel, è il primo nome che ti fanno.",
      "Sul Mac, però, si vedono le sue origini multipiattaforma. L'immagine disco per Apple silicon pesa circa 300 MB, installa un'intera suite anche se ti servono solo i fogli di calcolo, e interfaccia, finestre di dialogo e scorciatoie non sembrano davvero parte di macOS. Foglio è un compromesso diverso: molto più piccolo, nativo, e dedicato solo ai fogli di calcolo.",
    ],
    sections: [
      {
        heading: "Due app gratuite e open source con obiettivi diversi",
        body: [
          "Entrambe sono gratuite e open source, ed entrambe funzionano completamente offline, senza account e senza telemetria. La differenza è l'ambizione. LibreOffice vuole essere un'alternativa completa a Microsoft Office su ogni sistema desktop. Foglio vuole essere il modo più veloce e leggero per aprire e modificare i fogli Excel di tutti i giorni su un Mac, e nient'altro.",
        ],
        bullets: [
          "**Foglio:** interfaccia Swift/AppKit, motore in Rust, solo Mac, MIT / Apache-2.0, 7,5 MB di download, circa 19 MB installato.",
          "**LibreOffice:** suite in C++ con un proprio toolkit grafico, Windows, macOS e Linux, MPL-2.0, circa 300 MB di download, fino a 800 MB su disco secondo i requisiti ufficiali.",
        ],
      },
      {
        heading: "Dove Foglio è migliore",
        body: [],
        bullets: [
          "**Dimensioni e avvio.** Foglio mostra una finestra pronta in 0,24 s e usa circa 58 MB di memoria con un foglio vuoto, con la CPU allo 0 % a riposo.",
          "**Un'app Mac nativa.** Veri documenti macOS, pannelli nelle finestre, modalità scura, finestre Apri e Salva standard, zoom con le dita, scorrimento fluido su una griglia su misura e scorciatoie di Excel per Mac.",
          "**Il modo di lavorare di Excel.** `.xlsx` è il formato di Foglio, non un filtro di importazione. I nomi delle funzioni sono quelli di Excel in italiano (`CERCA.VERT`, `SOMMA.PIÙ.SE`, `SE.ERRORE`).",
          "**Funzioni moderne di Excel.** Foglio supporta LAMBDA oltre a CERCA.X, FILTRO, ORDINA e LET. LibreOffice ha aggiunto CERCA.X, FILTRO e LET nel 2024 ma, mentre scriviamo, non implementa LAMBDA.",
          "**Velocità sulle cartelle grandi.** Grazie al ricalcolo incrementale e alle ricerche indicizzate, una modifica in una cartella da 100.000 righe e 300.000 formule si ricalcola in 16 ms sul nostro Mac di prova.",
        ],
      },
      {
        heading: "Dove LibreOffice Calc è migliore",
        body: ["LibreOffice ha decenni di sviluppo alle spalle e per molti lavori è semplicemente più capace:"],
        bullets: [
          "**Tabelle pivot** (con campi calcolati nelle versioni recenti). Foglio offre solo *Riepiloga per*.",
          "**Macro** in LibreOffice Basic e Python, con supporto parziale a VBA di Excel. Foglio non esegue macro.",
          "**Più tipi di grafico**, forme, strumenti di disegno e caselle di testo.",
          "**Salvataggio in più formati**, tra cui `.ods`, `.xls` e molti altri. Foglio apre `.xls` e `.ods` (valori, formule e date) ma salva solo in `.xlsx`, CSV e PDF.",
          "**File protetti da password**, barre dei dati, set di icone e sparkline, che Foglio non supporta ancora.",
          "**Una suite intera**: Writer, Impress, Draw e Base nello stesso download.",
          "**Versioni per Windows e Linux**, se lavori su più sistemi.",
        ],
      },
      {
        heading: "Quando conviene tenere LibreOffice",
        body: [
          "Tieni LibreOffice se ti servono tabelle pivot o macro, se usi OpenDocument come formato principale, se ti servono anche un elaboratore di testi e le presentazioni, o se usi la stessa suite su Windows o Linux. È un progetto maturo e affidabile, e tenerlo installato non costa nulla.",
          "Scegli Foglio se in pratica apri i fogli che ti mandano, correggi qualche numero e li rimandi, e vuoi un'app che parta all'istante, sembri parte del tuo Mac e non occupi 800 MB di disco per farlo. Le due app convivono senza problemi: imposta Foglio come predefinita per `.xlsx` e `.csv` e apri LibreOffice per i lavori che lo richiedono.",
        ],
      },
      {
        heading: "Cambiare è facile, perché i file sono gli stessi",
        body: [
          "Non c'è nessuna migrazione. Entrambe le app leggono e scrivono `.xlsx`, quindi un file modificato nell'una si apre nell'altra. Se hai file `.ods`, Foglio ne apre valori, formule e date e li salva in `.xlsx`; la formattazione dei file `.ods` per ora non viene importata, quindi conserva gli originali. Lo stesso vale per i vecchi `.xls`: vedi [come aprire i file .xls su Mac](/guides/open-xls-on-mac/).",
          "[Scarica Foglio](/download/), provalo con qualche file vero e guarda la [tabella di confronto](/compare/) per i dettagli. Se ti incuriosisce come faccia a essere così piccolo, leggi [come è fatto Foglio](/technology/).",
        ],
      },
    ],
    faq: [
      {
        q: "Foglio è basato su LibreOffice?",
        a: "No. Foglio è un progetto separato. L'interfaccia è scritta in Swift/AppKit e il motore delle formule è un fork migliorato di IronCalc, un motore open source in Rust. Per leggere `.xls`, `.xlsb` e `.ods` usa la libreria Rust calamine.",
      },
      {
        q: "Sono entrambi gratuiti anche per uso commerciale?",
        a: "Sì. LibreOffice è distribuito con licenza MPL-2.0, Foglio con MIT e Apache-2.0. Entrambi si possono usare al lavoro senza costi.",
      },
      {
        q: "Quale apre meglio i file Excel?",
        a: "Dipende dal file. LibreOffice supporta più funzionalità di Excel nel complesso (tabelle pivot, macro, forme). Foglio tratta `.xlsx` come formato nativo e dà gli stessi risultati di Excel su 191 delle 195 funzioni verificate. Prova i tuoi file in entrambi.",
      },
      {
        q: "Foglio salva i file .ods?",
        a: "No. Foglio apre gli `.ods` e li salva in `.xlsx`. Se devi mantenere i file in formato OpenDocument, usa LibreOffice.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Alternativa leggera a LibreOffice Calc",
    cardText: "Un foglio di calcolo nativo da 7,5 MB per i file Excel di ogni giorno, e quando LibreOffice resta la scelta migliore.",
  },

  // ───────────────────────────────────────────────────────────────────
  {
    slug: "google-sheets",
    meta: {
      title: "Alternativa offline a Fogli Google per Mac | Foglio",
      description:
        "Vuoi fogli di calcolo che funzionano offline e restano sul tuo Mac? Foglio è un'app gratuita e riservata, senza account. Quando Fogli Google resta meglio.",
    },
    h1: "Un'alternativa offline e riservata a Fogli Google per Mac",
    intro: [
      "Fogli Google è gratuito, capace e imbattibile quando più persone devono modificare lo stesso foglio nello stesso momento. Ma ha delle condizioni: serve un account Google, i file stanno sui server di Google, funziona in una scheda del browser, e lavorare offline richiede Chrome o Edge, un'estensione e una configurazione fatta in anticipo.",
      "Foglio è un'app gratuita e open source per fogli di calcolo che funziona interamente sul tuo Mac. Nessun account, nessun accesso, nessuna connessione di rete di sua iniziativa. I tuoi file sono normali `.xlsx` in una cartella che scegli tu. Ecco come si confrontano, con onestà.",
    ],
    sections: [
      {
        heading: "Perché si cerca un'alternativa a Fogli Google",
        body: [],
        bullets: [
          "**Lavorare offline.** In aereo, in treno o con il Wi-Fi scadente di un albergo, un'app desktop funziona e basta. La modalità offline di Google va attivata quando sei online, richiede l'estensione Documenti Google offline in Chrome o Edge e può usarla un solo account per profilo del browser.",
          "**Privacy.** Alcuni dati non dovrebbero essere caricati da nessuna parte: buste paga, spese mediche, elenchi di clienti. Con Foglio il file non lascia il tuo Mac a meno che non sia tu a inviarlo.",
          "**Nessun account.** Non tutti hanno, o vogliono, un account Google, e alcune aziende non consentono archivi cloud personali.",
          "**Una vera app per Mac.** Una scheda del browser non è un'app Mac: niente Apri recenti, niente finestre proprie, niente finestra di stampa nativa, niente scorciatoie del Mac. Foglio è scritto in Swift/AppKit.",
          "**File locali grandi.** Aprire un `.xlsx` grande in Fogli Google significa caricarlo e convertirlo, e Google pone un limite di 20 milioni di celle per foglio. Foglio apre una cartella da 100.000 righe e 300.000 formule in 1,1 s sul nostro Mac di prova.",
        ],
      },
      {
        heading: "Cosa ritrovi di Fogli Google",
        body: [
          "La maggior parte di quello che fai in Fogli Google funziona allo stesso modo in Foglio. Le formule usano la stessa sintassi in stile Excel: SOMMA.PIÙ.SE, CERCA.X, FILTRO, ORDINA, LET e LAMBDA ci sono tutte, tra circa 500 funzioni. Filtro automatico, ordinamento, elenchi a discesa con la convalida dati, formattazione condizionale con scale di colori, grafici, trova e sostituisci, riquadri bloccati e note sono supportati.",
          "Per portare un foglio in Foglio, in Fogli Google scegli File ▸ Scarica ▸ Microsoft Excel (.xlsx) e apri il file in Foglio. Formattazione, formule e grafici arrivano integri; le funzioni esclusive di Google come GOOGLEFINANCE, IMPORTRANGE o QUERY non hanno un equivalente né in Foglio né in Excel.",
        ],
      },
      {
        heading: "Cosa fa meglio Fogli Google",
        body: [],
        bullets: [
          "**Collaborazione in tempo reale.** Più cursori nello stesso foglio, commenti con menzioni, cronologia delle versioni. Foglio è un'app desktop per una persona alla volta.",
          "**Ogni dispositivo.** Fogli Google funziona in qualsiasi browser e ha app per iPhone, iPad e Android. Foglio funziona solo sui Mac con macOS 14 o successivo.",
          "**Dati online.** Funzioni come IMPORTRANGE, IMPORTHTML e GOOGLEFINANCE importano dati dal web in tempo reale. Foglio non si collega a Internet.",
          "**Automazione e IA.** Apps Script per l'automazione e, a seconda del piano, Gemini per aiutarti con formule e analisi. Foglio non ha né macro né funzioni di IA.",
          "**Tabelle pivot e più tipi di grafico.** Foglio offre *Riepiloga per* per i riepiloghi semplici e i tipi di grafico più comuni.",
        ],
      },
      {
        heading: "Quando conviene continuare con Fogli Google",
        body: [
          "Se il tuo foglio è uno spazio condiviso, come il piano di lavoro di un team, la lista per le vacanze di famiglia o un foglio di iscrizioni, Fogli Google è lo strumento giusto e Foglio non cerca di sostituirlo. Lo stesso vale per i fogli che importano dati dal web o che devi modificare dal telefono.",
          "Se il foglio è tuo, locale o riservato, un'app desktop ha più senso. Molti usano entrambi: Fogli Google per i documenti condivisi, Foglio per le finanze personali, i dati dei clienti e i file Excel che arrivano per email.",
        ],
      },
      {
        heading: "I tuoi file, nella tua cartella",
        body: [
          "Foglio salva normali file `.xlsx` dove preferisci: nella cartella Documenti, su un disco esterno o, se lo scegli tu, in una cartella sincronizzata come iCloud Drive o Dropbox. Essendo file Excel, puoi sempre caricarne uno su Fogli Google in seguito. Nessun vincolo, in nessuna direzione.",
          "[Scarica Foglio](/download/) gratis (7,5 MB, macOS 14+). Per vedere come si confronta anche con Excel, Numbers e LibreOffice, leggi il [confronto completo](/compare/).",
        ],
      },
    ],
    faq: [
      {
        q: "Fogli Google funziona offline sul Mac?",
        a: "Sì, con dei limiti: servono Chrome o Microsoft Edge e l'estensione Documenti Google offline, e l'accesso offline va attivato mentre sei connesso. Può usarlo un solo account per profilo del browser. Un'app desktop come Foglio, Numbers, LibreOffice o Excel funziona offline senza configurazioni.",
      },
      {
        q: "Foglio carica i miei file da qualche parte?",
        a: "No. Foglio non ha account, archivio cloud né telemetria, e non apre connessioni di rete di sua iniziativa. Apre una pagina web solo quando fai clic su un collegamento in una cella.",
      },
      {
        q: "Posso aprire un file di Fogli Google in Foglio?",
        a: "Prima scaricalo con File ▸ Scarica ▸ Microsoft Excel (.xlsx) in Fogli Google, poi apri l'`.xlsx` in Foglio. Il file `.gsheet` creato da Google Drive per desktop è solo un collegamento e non si può aprire offline.",
      },
      {
        q: "Le mie formule di Fogli Google funzionano in Foglio?",
        a: "Quelle standard sì, perché entrambi seguono la sintassi di Excel. Le funzioni specifiche di Google come QUERY, IMPORTRANGE, GOOGLEFINANCE e SPARKLINE non sono disponibili in Foglio.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Alternativa offline a Fogli Google",
    cardText: "Un foglio di calcolo desktop gratuito, senza account e senza cloud, e quando Fogli Google resta la scelta giusta.",
  },
];

export const alternatives: Record<Locale, Article[]> = { en, it };
