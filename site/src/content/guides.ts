import type { Article, Locale } from "./types";

const UPDATED = "2026-11-09";

/** English → Italian Excel function names, used by the translation guide in both languages. */
const FN_PAIRS: [string, string][] = [
  ["SUM", "SOMMA"],
  ["SUMIF", "SOMMA.SE"],
  ["SUMIFS", "SOMMA.PIÙ.SE"],
  ["SUMPRODUCT", "MATR.SOMMA.PRODOTTO"],
  ["AVERAGE", "MEDIA"],
  ["AVERAGEIF", "MEDIA.SE"],
  ["COUNT", "CONTA.NUMERI"],
  ["COUNTA", "CONTA.VALORI"],
  ["COUNTBLANK", "CONTA.VUOTE"],
  ["COUNTIF", "CONTA.SE"],
  ["COUNTIFS", "CONTA.PIÙ.SE"],
  ["ROUND", "ARROTONDA"],
  ["ROUNDUP", "ARROTONDA.PER.ECC"],
  ["ROUNDDOWN", "ARROTONDA.PER.DIF"],
];
const LOGIC_PAIRS: [string, string][] = [
  ["IF", "SE"],
  ["IFS", "PIÙ.SE"],
  ["IFERROR", "SE.ERRORE"],
  ["IFNA", "SE.NON.DISP."],
  ["AND", "E"],
  ["OR", "O"],
  ["NOT", "NON"],
];
const LOOKUP_PAIRS: [string, string][] = [
  ["VLOOKUP", "CERCA.VERT"],
  ["HLOOKUP", "CERCA.ORIZZ"],
  ["XLOOKUP", "CERCA.X"],
  ["INDEX", "INDICE"],
  ["MATCH", "CONFRONTA"],
  ["INDIRECT", "INDIRETTO"],
  ["OFFSET", "SCARTO"],
  ["FILTER", "FILTRO"],
  ["SORT", "ORDINA"],
];
const TEXT_PAIRS: [string, string][] = [
  ["LEFT", "SINISTRA"],
  ["RIGHT", "DESTRA"],
  ["MID", "STRINGA.ESTRAI"],
  ["LEN", "LUNGHEZZA"],
  ["TRIM", "ANNULLA.SPAZI"],
  ["UPPER", "MAIUSC"],
  ["LOWER", "MINUSC"],
  ["SUBSTITUTE", "SOSTITUISCI"],
  ["CONCATENATE", "CONCATENA"],
  ["TEXTJOIN", "TESTO.UNISCI"],
  ["TEXT", "TESTO"],
  ["VALUE", "VALORE"],
];
const DATE_PAIRS: [string, string][] = [
  ["TODAY", "OGGI"],
  ["NOW", "ADESSO"],
  ["YEAR", "ANNO"],
  ["MONTH", "MESE"],
  ["DAY", "GIORNO"],
  ["WEEKDAY", "GIORNO.SETTIMANA"],
  ["EDATE", "DATA.MESE"],
  ["EOMONTH", "FINE.MESE"],
  ["DATEDIF", "DATA.DIFF"],
  ["NETWORKDAYS", "GIORNI.LAVORATIVI.TOT"],
];
const pairs = (list: [string, string][], dir: "en-it" | "it-en") =>
  list.map(([e, i]) => (dir === "en-it" ? `\`${e}\` → \`${i}\`` : `\`${i}\` → \`${e}\``));

const en: Article[] = [
  // ───────────────────────────────────────────────────────────────────
  {
    slug: "open-xlsx-on-mac-without-excel",
    meta: {
      title: "How to Open xlsx Files on a Mac Without Excel | Foglio",
      description:
        "Four free ways to open and edit Excel xlsx files on a Mac without Microsoft Excel: Quick Look, Numbers, a free desktop app, or a browser. Pros and cons.",
    },
    h1: "How to open xlsx files on a Mac without Excel",
    intro: [
      "Someone emailed you a spreadsheet, you double-click it, and your Mac either opens Numbers, asks which app to use, or tells you that you need a Microsoft 365 subscription. You do not need to buy Excel to read or edit an `.xlsx` file. Here are the free options, from quickest to most capable, with the trade-offs of each.",
    ],
    sections: [
      {
        heading: "1. Just look at it: Quick Look",
        body: [
          "If you only need to read the file, select it in Finder and press the **Space bar**. Quick Look shows a preview of the sheets without opening any app. You cannot edit, sort or copy formulas, and complex files may not preview accurately, but it is instant and built in.",
        ],
      },
      {
        heading: "2. Edit it in a free desktop app",
        body: [
          "To change the file and send it back as `.xlsx`, a desktop app that treats Excel's format as its own is the most direct route. [Foglio](/) is a free, open-source Mac app built for exactly this: it opens and saves `.xlsx` with formatting, formulas, charts, pictures and comments, and uses Excel's function names and keyboard shortcuts.",
        ],
        sub: [
          {
            heading: "Steps with Foglio",
            body: [],
            bullets: [
              "[Download Foglio](/download/) (7.5 MB, macOS 14 or later) and drag it to Applications.",
              "The first time, confirm the macOS security prompt: on macOS 15 or later go to System Settings ▸ Privacy & Security ▸ **Open Anyway**; on macOS 14 right-click the app and choose **Open**.",
              "Right-click your `.xlsx` file in Finder and choose **Open With ▸ Foglio**, or drag it onto the Foglio icon.",
              "Edit, then press ⌘S. The file is saved as `.xlsx`, ready to send back.",
            ],
          },
          {
            heading: "What to watch for",
            body: [
              "Foglio does not run macros, has no real pivot tables, skips shapes and SmartArt, and cannot open password-protected files. For ordinary spreadsheets that is rarely a problem, but keep the original of anything complex. [LibreOffice Calc](/alternatives/libreoffice/) is another free desktop option, larger but with pivot tables and macros.",
            ],
          },
        ],
      },
      {
        heading: "3. Use Apple Numbers",
        body: [
          "Numbers is free from Apple and often already installed. Right-click the file and choose **Open With ▸ Numbers**. Numbers imports the workbook and converts it to a Numbers document; when you are done, use **File ▸ Export To ▸ Excel** to create an `.xlsx` again. If you just press ⌘S you get a `.numbers` file, which Excel users cannot open.",
          "This works well for simple files. Large sheets, some formulas and formatting may change in the round trip, and the current Numbers requires macOS 26. See [Numbers vs Foglio](/alternatives/numbers/) for the details.",
        ],
      },
      {
        heading: "4. Use a browser: Excel for the web or Google Sheets",
        body: [
          "**Excel for the web** is free with a Microsoft account: upload the file to OneDrive and open it in the browser. It is real Excel, minus some desktop features. **Google Sheets** can open `.xlsx` files uploaded to Google Drive, either converting them or editing them in Office compatibility mode in Chrome; download as `.xlsx` when you are done.",
          "Both need an internet connection and an account, and both mean uploading the file to a cloud service. Avoid this route for confidential data such as payroll or medical records. More on this in [the Google Sheets alternative](/alternatives/google-sheets/) page.",
        ],
      },
      {
        heading: "Make your choice stick: set the default app",
        body: [
          "To make every `.xlsx` open in the app you prefer, select one in Finder, press ⌘I (Get Info), choose the app under **Open with**, and click **Change All…**.",
        ],
      },
      {
        heading: "Which option should you pick?",
        bullets: [
          "**Only reading:** Quick Look.",
          "**Editing and sending back, privately and offline:** a free desktop app such as Foglio or LibreOffice.",
          "**Beautiful documents for yourself:** Numbers.",
          "**Working on the file with others at the same time:** Excel for the web or Google Sheets.",
        ],
        body: ["The [comparison page](/compare/) lays out all the differences side by side."],
      },
    ],
    faq: [
      {
        q: "Can a Mac open xlsx files without any extra software?",
        a: "You can preview them with Quick Look (select the file and press Space). To edit them you need an app: Numbers is free from Apple, and Foglio and LibreOffice are free downloads.",
      },
      {
        q: "Why does my xlsx file open in Numbers?",
        a: "Numbers is the default app for spreadsheets on many Macs. Change it with Get Info ▸ Open with ▸ Change All… in Finder.",
      },
      {
        q: "What about .xlsm files with macros?",
        a: "Free apps open the data, but only Excel runs VBA macros reliably. Foglio opens `.xlsm` files without running the macros, and they are not kept when you save.",
      },
      {
        q: "Is it safe to upload work files to an online viewer?",
        a: "It depends on the file and your company's rules. Free online converters and viewers receive a copy of your data. A desktop app keeps the file on your Mac.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Open xlsx files without Excel",
    cardText: "Quick Look, Numbers, a free desktop app or a browser: four free ways to open and edit Excel files on a Mac.",
  },

  // ───────────────────────────────────────────────────────────────────
  {
    slug: "open-xls-on-mac",
    meta: {
      title: "How to Open Old .xls Excel Files on a Mac | Foglio",
      description:
        "Got an old .xls file from Excel 97–2003 that Numbers refuses? How to open legacy xls on a Mac for free, convert it to xlsx, and fix files that are not xls.",
    },
    h1: "How to open old .xls Excel files on a Mac",
    intro: [
      "`.xls` is the binary format Excel used before 2007, and it is still everywhere: bank exports, accounting software, government data, archives. Modern Mac apps handle it less gracefully than `.xlsx`. Numbers, for example, can refuse some files with a message that the document was created with an unsupported version of Excel.",
      "Here is how to open an `.xls` file on a Mac for free, how to convert it to the modern `.xlsx` format, and what to do when the file is not really an `.xls` at all.",
    ],
    sections: [
      {
        heading: "Option 1: open it in Foglio and save as xlsx",
        body: [
          "[Foglio](/) is a free, open-source spreadsheet app for the Mac. It reads `.xls` files with calamine, a fast Rust library for legacy Excel formats, and also opens binary `.xlsb` files.",
        ],
        bullets: [
          "[Download Foglio](/download/) and drag it to Applications.",
          "Right-click the `.xls` file and choose **Open With ▸ Foglio** (or use File ▸ Open in Foglio).",
          "Check the data, then choose **File ▸ Save As…** to save an `.xlsx` copy. Foglio does not write the old `.xls` format.",
        ],
        sub: [
          {
            heading: "What comes across",
            body: [
              "From `.xls` and `.xlsb` files Foglio imports **values, formulas and dates**, on every sheet. Cell formatting such as fonts, colors and borders is not imported from these legacy formats yet, and macros are never run. If you need the original look of an old workbook, LibreOffice or Excel will preserve more of it.",
            ],
          },
        ],
      },
      {
        heading: "Option 2: LibreOffice Calc",
        body: [
          "LibreOffice Calc is free, open source and has decades of experience with `.xls`, including formatting. It can also save back to `.xls` if a system you use still requires it. It is a larger download (about 300 MB for Apple silicon) and not a native Mac app, but for archives of old workbooks it is very thorough. See [LibreOffice vs Foglio](/alternatives/libreoffice/).",
        ],
      },
      {
        heading: "Option 3: Numbers or Excel",
        body: [
          "Numbers opens many `.xls` files: right-click ▸ Open With ▸ Numbers. If it refuses, convert the file to `.xlsx` with Foglio or LibreOffice first and then import that into Numbers. Microsoft Excel, of course, opens any `.xls`, but needs a subscription or a license to edit.",
        ],
      },
      {
        heading: "When the “.xls” is not an xls",
        body: [
          "Many websites and older business systems export files named `.xls` that are actually something else. If a file shows strange tags, everything in one column or garbled text, check what it really is:",
        ],
        bullets: [
          "**HTML tables.** Some systems write a web page and call it `.xls`. Open it in TextEdit; if you see `<table>` or `<html>`, rename the copy to `.html` and open it in a browser, or copy the table into a spreadsheet.",
          "**Tab- or comma-separated text.** If TextEdit shows plain rows of text, rename the copy to `.csv` or `.txt`. Foglio opens these with automatic detection of encoding, delimiter and decimal separator; see [how to open CSV files on a Mac](/guides/open-csv-on-mac/).",
          "**An `.xlsx` with the wrong extension.** If the file is really an `.xlsx` (it starts with the letters `PK` in TextEdit), rename the copy to `.xlsx`.",
          "**SpreadsheetML (XML).** Excel 2003 XML files start with `<?xml` and mention `urn:schemas-microsoft-com:office:spreadsheet`. Foglio does not read them; LibreOffice and Excel do.",
        ],
      },
      {
        heading: "Converting many .xls files",
        body: [
          "Foglio converts one file at a time. For a large archive, LibreOffice can convert in bulk from the Terminal with its `--convert-to xlsx` command-line option. Whatever you use, keep the original `.xls` files until you have checked the results.",
        ],
      },
    ],
    faq: [
      {
        q: "What is the difference between xls and xlsx?",
        a: "`.xls` is Excel's binary format from 1997–2003. `.xlsx` is the XML-based format Excel has used since 2007. `.xlsx` files are smaller, more robust and supported by every modern app.",
      },
      {
        q: "Can Foglio save .xls files?",
        a: "No. Foglio opens `.xls` and saves as `.xlsx`. If you need to write `.xls`, use LibreOffice or Excel.",
      },
      {
        q: "Why does Numbers say the file was made with an unsupported version of Excel?",
        a: "Numbers does not import some older `.xls` variants. Open the file in Foglio or LibreOffice, save it as `.xlsx`, and Numbers will be able to import it.",
      },
      {
        q: "Are old xls files with macros dangerous?",
        a: "Macros can contain harmful code. Foglio never runs macros, so opening an `.xls` or `.xlsm` in it does not execute them. Be careful about enabling macros in Excel for files you did not expect.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Open old .xls files on a Mac",
    cardText: "Open legacy Excel 97–2003 files for free, convert them to xlsx, and spot exports that are not really xls.",
  },

  // ───────────────────────────────────────────────────────────────────
  {
    slug: "open-csv-on-mac",
    meta: {
      title: "Open CSV Files on a Mac: Fix Columns and Encoding | Foglio",
      description:
        "CSV opening in one column, with garbled accents or wrong decimals? Why it happens on a Mac and how to open CSV files correctly, with or without Excel.",
    },
    h1: "How to open CSV files on a Mac (and fix columns, accents and decimals)",
    intro: [
      "CSV looks like the simplest format there is: rows of text, values separated by commas. In practice it is the source of endless small disasters. Everything lands in column A. Accented letters turn into `Ã©`. Prices of `1,50` become `150`. Leading zeros vanish from postcodes.",
      "This guide explains the three things that go wrong, how to open a CSV correctly on a Mac with or without Excel, and how to save one that others can open.",
    ],
    sections: [
      {
        heading: "Why CSV files open wrong",
        sub: [
          {
            heading: "1. The delimiter",
            body: [
              "Despite the name, many CSV files are not comma-separated. In countries that write decimals with a comma (Italy, Germany, France, Spain and many more), Excel exports CSV with **semicolons**. Other systems use tabs or vertical bars. If the app guesses the wrong delimiter, every row ends up in a single column.",
            ],
          },
          {
            heading: "2. The text encoding",
            body: [
              "A CSV file does not say which character encoding it uses. Modern files are usually UTF-8, but exports from older Windows software are often Windows-1252, and some tools write UTF-16. Read with the wrong encoding, `é` becomes `Ã©` and `€` becomes nonsense.",
            ],
          },
          {
            heading: "3. The decimal separator",
            body: [
              "`1,500` means one and a half in Italy and one thousand five hundred in the US. If the app reads numbers with your Mac's convention instead of the file's, values are silently wrong, which is worse than a visible error.",
            ],
          },
        ],
        body: [],
      },
      {
        heading: "The easy way: an app that detects all three",
        body: [
          "[Foglio](/) is a free, open-source spreadsheet app for the Mac that looks at the file before importing it:",
        ],
        bullets: [
          "**Delimiter:** chooses between comma, semicolon, tab and vertical bar by checking which one splits the first rows most consistently, ignoring separators inside quotes.",
          "**Encoding:** reads UTF-8 (with or without a byte-order mark) and UTF-16, and falls back to Windows-1252 for older Western European exports.",
          "**Decimals:** works out whether the file writes `1.234,56` or `1,234.56` and reads every number accordingly, whatever your Mac's region.",
          "**Safety:** text that starts with `=` is kept as text, never run as a formula, so a malicious CSV cannot trigger calculations.",
        ],
        sub: [
          {
            heading: "Steps",
            body: [
              "[Download Foglio](/download/), then right-click the `.csv` file and choose **Open With ▸ Foglio**. `.tsv` and `.txt` files work the same way. When you are done, save it as an Excel workbook (`.xlsx`) to keep formulas and formatting, or as CSV again.",
            ],
          },
        ],
      },
      {
        heading: "Other ways to open a CSV on a Mac",
        bullets: [
          "**Numbers:** double-click or Open With ▸ Numbers. It works well for clean UTF-8 comma files; with semicolons or other encodings, check the import settings and the result carefully.",
          "**Excel:** use **Data ▸ Get Data ▸ From Text/CSV** (or the older From Text wizard) instead of double-clicking, so you can choose the delimiter, the encoding (File Origin) and the column types.",
          "**LibreOffice Calc:** shows a Text Import dialog where you choose character set, separators and column types. Very thorough.",
          "**Google Sheets:** File ▸ Import ▸ Upload, with automatic or custom separator detection. Requires uploading the data.",
          "**TextEdit:** not a spreadsheet, but useful for checking what is really inside the file.",
        ],
        body: [],
      },
      {
        heading: "Keep leading zeros and long numbers",
        body: [
          "Postcodes, product codes and phone numbers like `00123` look like numbers to any spreadsheet and lose their zeros. Long IDs such as card or IBAN-like numbers get rounded beyond 15 digits. If these columns matter, ask for the export with those values in quotes and a prefix, open the CSV in an app that lets you set columns to Text during import (Excel's import wizard, LibreOffice), or keep the original file untouched for reference.",
        ],
      },
      {
        heading: "Saving a CSV others can open",
        body: [
          "CSV holds only the values of one sheet: no formulas, formatting or other sheets. Foglio warns you before saving and offers to save as an Excel workbook instead. When you do save CSV, Foglio writes UTF-8 with a byte-order mark (so Excel recognizes the encoding) and uses `;` as the delimiter on Macs set to a decimal-comma region, like Excel does.",
          "If the file is going to someone in another country, tell them which delimiter and decimal separator you used, or send an `.xlsx` instead. It avoids every problem on this page. For Excel files, see [how to open xlsx files without Excel](/guides/open-xlsx-on-mac-without-excel/).",
        ],
      },
    ],
    faq: [
      {
        q: "Why does my CSV open in only one column?",
        a: "The app used the wrong delimiter: usually the file uses semicolons and the app expected commas, or vice versa. Use an import dialog to choose the delimiter, or an app such as Foglio that detects it automatically.",
      },
      {
        q: "How do I fix strange characters like Ã© in a CSV?",
        a: "The file was read with the wrong text encoding, typically UTF-8 read as Windows-1252 or the reverse. Re-open it choosing the right encoding (UTF-8 is the usual answer), or with an app that detects it.",
      },
      {
        q: "How do I open a CSV with decimal commas on a US-English Mac?",
        a: "Foglio detects the file's decimal convention and reads `1,5` as one and a half regardless of your Mac's region. In Excel, use the text import and set the decimal separator in the advanced options.",
      },
      {
        q: "Is CSV or xlsx better for sharing?",
        a: "`.xlsx` keeps formulas, formatting and several sheets and has no encoding or delimiter ambiguity. Use CSV when a system specifically asks for it.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Open CSV files on a Mac",
    cardText: "Fix one-column CSVs, garbled accents and wrong decimal commas, with or without Excel.",
  },

  // ───────────────────────────────────────────────────────────────────
  {
    slug: "free-spreadsheet-apps-for-mac",
    meta: {
      title: "Free Spreadsheet Apps for Mac Compared (2026) | Foglio",
      description:
        "The free spreadsheet apps for Mac worth knowing in 2026: Numbers, LibreOffice, Google Sheets, Excel for the web, ONLYOFFICE and Foglio. Who each is for.",
    },
    h1: "Free spreadsheet apps for Mac: an honest roundup",
    intro: [
      "You do not need to pay for a spreadsheet on a Mac. There are several genuinely free options, and each is good at something different. This roundup is written by the Foglio project, so take our enthusiasm for Foglio with that in mind; we have tried to be fair about where the others are better.",
      "“Free” here means you can create, edit and save spreadsheets at no cost, without a trial period.",
    ],
    sections: [
      {
        heading: "Apple Numbers",
        body: [
          "**Best for:** good-looking personal documents and Apple-device users.",
          "Numbers is free, often pre-installed, and runs on Mac, iPhone and iPad with iCloud sync and real-time collaboration. Its canvas of free-floating tables and its templates make documents look polished with little effort. Premium templates and AI features need an Apple Creator Studio subscription, but the core app is free.",
          "**Watch out for:** Excel files are imported and converted to `.numbers`, so you must export back to `.xlsx`; the current version requires macOS 26. More in [Numbers vs Foglio](/alternatives/numbers/).",
        ],
      },
      {
        heading: "LibreOffice Calc",
        body: [
          "**Best for:** the most complete free desktop spreadsheet, and OpenDocument users.",
          "LibreOffice is open source (MPL-2.0) and runs on macOS, Windows and Linux. Calc has pivot tables, macros in Basic and Python with partial VBA support, a vast function library and excellent import and export of old formats. It works offline with no account and no AI features by design.",
          "**Watch out for:** about 300 MB to download, a whole office suite installed, and an interface that does not feel native on macOS. More in [LibreOffice vs Foglio](/alternatives/libreoffice/).",
        ],
      },
      {
        heading: "Google Sheets",
        body: [
          "**Best for:** working on the same sheet with other people.",
          "Google Sheets runs in any browser and on phones, with the best real-time collaboration around, version history, Apps Script automation and functions that pull data from the web.",
          "**Watch out for:** you need a Google account, files live on Google's servers, and offline use requires Chrome or Edge with an extension. More in [the Google Sheets alternative](/alternatives/google-sheets/).",
        ],
      },
      {
        heading: "Excel for the web",
        body: [
          "**Best for:** occasional Excel users who want the real thing for free.",
          "Microsoft offers Excel in the browser at no cost with a Microsoft account. It opens `.xlsx` files faithfully, because it is Excel, and supports co-authoring through OneDrive.",
          "**Watch out for:** it needs an internet connection and OneDrive, and some desktop features (such as running VBA macros) are not available. The desktop Excel for Mac needs a subscription or license to edit.",
        ],
      },
      {
        heading: "ONLYOFFICE Desktop Editors",
        body: [
          "**Best for:** people who want a free, Office-like suite with a familiar ribbon interface.",
          "ONLYOFFICE Desktop Editors is a free, open-source (AGPL-3.0) suite for Mac, Windows and Linux that uses Office Open XML (`.xlsx`) as its native format and includes a spreadsheet editor with pivot tables.",
          "**Watch out for:** it is a cross-platform app built on web technology, so it is a larger download and feels less Mac-like than a native app.",
        ],
      },
      {
        heading: "Foglio",
        body: [
          "**Best for:** opening and editing everyday Excel files quickly, privately and natively.",
          "Foglio is free and open source (MIT / Apache-2.0), written in Swift/AppKit with a Rust engine. It is a 7.5 MB download, opens in 0.24 s, edits `.xlsx` directly, understands about 500 Excel functions in your language (`=SOMMA()` on an Italian Mac), and detects CSV encodings and delimiters. No account, no telemetry, no network connections of its own.",
          "**Watch out for:** it is a 1.0 release; there are no pivot tables (only a simpler *Summarize by*), no macros, no collaboration, no iPhone or iPad version, and it cannot open password-protected files. See the [full comparison](/compare/).",
        ],
      },
      {
        heading: "Quick guide: which free app for which job",
        bullets: [
          "**Excel attachments you need to edit and send back:** Foglio, LibreOffice or Excel for the web.",
          "**A shared family or team sheet:** Google Sheets or Numbers.",
          "**Pivot tables or macros, offline, for free:** LibreOffice Calc.",
          "**Pretty personal budgets and lists:** Numbers.",
          "**Confidential data that must not leave your Mac:** a desktop app with no cloud: Foglio, LibreOffice or Numbers with iCloud turned off for it.",
          "**An old Mac:** LibreOffice supports macOS 11 and Foglio macOS 14; the newest Numbers needs macOS 26.",
        ],
        body: [],
      },
    ],
    faq: [
      {
        q: "Is there a completely free Excel for Mac?",
        a: "Excel for the web is free with a Microsoft account; the desktop Excel for Mac needs a subscription or license to edit. Free desktop apps that open and save Excel files include Foglio, LibreOffice Calc and ONLYOFFICE.",
      },
      {
        q: "Which free spreadsheet app is most compatible with Excel?",
        a: "Excel for the web, because it is Excel. Among desktop apps, LibreOffice supports the most Excel features overall, while Foglio and ONLYOFFICE use `.xlsx` as their native format. Test your own files: compatibility depends on what is in them.",
      },
      {
        q: "Which one is the lightest?",
        a: "Foglio, at a 7.5 MB download and about 19 MB installed. Google Sheets and Excel for the web install nothing but need a browser and an internet connection.",
      },
      {
        q: "Are these apps free for business use?",
        a: "Foglio (MIT / Apache-2.0), LibreOffice (MPL-2.0) and ONLYOFFICE Desktop Editors (AGPL-3.0) can be used at work at no cost. Numbers is free for everyone. Google and Microsoft offer paid business plans with extra features.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Free spreadsheet apps for Mac",
    cardText: "Numbers, LibreOffice, Google Sheets, Excel for the web, ONLYOFFICE and Foglio: who each one is for.",
  },

  // ───────────────────────────────────────────────────────────────────
  {
    slug: "excel-functions-italian-english",
    meta: {
      title: "Excel Function Names in Italian and English | Foglio",
      description:
        "VLOOKUP is CERCA.VERT, SUM is SOMMA, IF is SE. A practical list of Excel function names in Italian and English, plus why formulas use semicolons in Italy.",
    },
    h1: "Excel function names in Italian and English",
    intro: [
      "Excel translates its function names. On an Italian Mac, `SUM` is `SOMMA`, `VLOOKUP` is `CERCA.VERT` and `IF` is `SE`, and arguments are separated by semicolons. That is great for Italian speakers and confusing for everyone following an English tutorial, or working with Italian colleagues.",
      "Below is a practical list of the most used functions in both languages, followed by the rules that trip people up: separators, decimal commas, and what happens when a file moves between languages.",
    ],
    sections: [
      {
        heading: "Math and statistics",
        body: [],
        bullets: pairs(FN_PAIRS, "en-it"),
      },
      {
        heading: "Logic",
        body: [],
        bullets: pairs(LOGIC_PAIRS, "en-it"),
      },
      {
        heading: "Lookup and dynamic arrays",
        body: [],
        bullets: pairs(LOOKUP_PAIRS, "en-it"),
      },
      {
        heading: "Text",
        body: [],
        bullets: pairs(TEXT_PAIRS, "en-it"),
      },
      {
        heading: "Dates",
        body: [
          "Many functions keep the same name in both languages, for example `MAX`, `MIN`, `LET` and `LAMBDA`.",
        ],
        bullets: pairs(DATE_PAIRS, "en-it"),
      },
      {
        heading: "Semicolons and decimal commas",
        body: [
          "Italy writes one and a half as `1,5`. Because the comma is taken, Italian Excel separates function arguments with a **semicolon**: `=SE(A1>1,5;\"sì\";\"no\")` is the Italian form of `=IF(A1>1.5,\"yes\",\"no\")`. Germany, France, Spain and most of continental Europe work the same way.",
          "This is decided by your Mac's region settings, not just the language: an English-language Mac set to an Italian region also uses decimal commas.",
        ],
      },
      {
        heading: "Files do not care which language you type in",
        body: [
          "An `.xlsx` file always stores formulas in English with commas: `SUM(A1:A10)`, not `SOMMA`. Each copy of Excel translates them into its user's language when it displays them. So an Italian and an American colleague can share the same file without anything breaking, as long as both apps follow this rule.",
          "Copy-pasting formula text is different: pasting `=VLOOKUP(A2,B:C,2,FALSE)` from an English website into Italian Excel gives an error. Translate the names with the list above and replace commas with semicolons.",
        ],
      },
      {
        heading: "Localized formulas in Foglio",
        body: [
          "[Foglio](/), the free open-source spreadsheet for Mac, follows the same convention as Excel. On an Italian Mac you type `=SOMMA(A1:A10;B2)`, `CERCA.VERT` or `SE.ERRORE` with semicolons and decimal commas, and get autocomplete with Italian descriptions; on disk the file keeps Excel's English form. German (`SUMME`, `SVERWEIS`), Spanish (`SUMA`, `BUSCARV`) and French (`SOMME`, `RECHERCHEV`) work the same way, and the Insert Function browser lists all ~500 functions under their localized names.",
          "Google Sheets and LibreOffice also localize function names based on your settings. Numbers does too. If you follow English tutorials, Show Formulas (View menu) in Foglio helps you compare what you typed with what the tutorial shows.",
        ],
      },
    ],
    faq: [
      {
        q: "What is VLOOKUP in Italian Excel?",
        a: "`CERCA.VERT`. Its arguments are the same, separated by semicolons: `=CERCA.VERT(A2;B:C;2;FALSO)`. XLOOKUP is `CERCA.X`.",
      },
      {
        q: "Why does my formula give an error in Italian Excel?",
        a: "Usually because it uses English names or commas between arguments. Use the Italian names and semicolons, and write decimals with a comma.",
      },
      {
        q: "Can I switch Excel to English function names?",
        a: "Excel follows the language of Office and your system. Foglio follows your Mac's language and region; changing them in System Settings ▸ General ▸ Language & Region changes the function names too.",
      },
      {
        q: "Will a file made in Italian Excel work in English Excel?",
        a: "Yes. The file stores formulas in English internally, so every version of Excel, and Foglio, shows them in its own language.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Excel functions: Italian ↔ English",
    cardText: "About 50 Excel function names translated, from SOMMA to CERCA.VERT, plus why Italian formulas use semicolons.",
  },
];

const it: Article[] = [
  // ───────────────────────────────────────────────────────────────────
  {
    slug: "open-xlsx-on-mac-without-excel",
    meta: {
      title: "Come aprire file xlsx su Mac senza Excel | Foglio",
      description:
        "Quattro modi gratuiti per aprire e modificare file Excel xlsx su Mac senza Microsoft Excel: Quick Look, Numbers, un'app desktop o il browser. Pro e contro.",
    },
    h1: "Come aprire i file xlsx su Mac senza Excel",
    intro: [
      "Qualcuno ti ha mandato un foglio di calcolo, fai doppio clic e il Mac apre Numbers, ti chiede quale app usare oppure ti avvisa che serve un abbonamento a Microsoft 365. Per leggere o modificare un file `.xlsx` non devi per forza comprare Excel. Ecco le soluzioni gratuite, dalla più rapida alla più completa, con i compromessi di ciascuna.",
    ],
    sections: [
      {
        heading: "1. Solo per guardarlo: Quick Look",
        body: [
          "Se ti basta leggere il file, selezionalo nel Finder e premi la **barra spaziatrice**. Quick Look mostra un'anteprima dei fogli senza aprire nessuna app. Non puoi modificare, ordinare o copiare le formule, e i file complessi possono non essere mostrati fedelmente, ma è immediato e già incluso nel Mac.",
        ],
      },
      {
        heading: "2. Modificarlo con un'app desktop gratuita",
        body: [
          "Per modificare il file e rimandarlo in formato `.xlsx`, la strada più diretta è un'app desktop che tratti il formato di Excel come proprio. [Foglio](/) è un'app per Mac gratuita e open source nata proprio per questo: apre e salva `.xlsx` con formattazione, formule, grafici, immagini e note, e usa i nomi delle funzioni di Excel in italiano e le sue scorciatoie da tastiera.",
        ],
        sub: [
          {
            heading: "I passaggi con Foglio",
            body: [],
            bullets: [
              "[Scarica Foglio](/download/) (7,5 MB, macOS 14 o successivo) e trascinalo in Applicazioni.",
              "La prima volta conferma l'avviso di sicurezza di macOS: su macOS 15 o successivi vai in Impostazioni di Sistema ▸ Privacy e sicurezza ▸ **Apri comunque**; su macOS 14 fai clic destro sull'app e scegli **Apri**.",
              "Fai clic destro sul file `.xlsx` nel Finder e scegli **Apri con ▸ Foglio**, oppure trascinalo sull'icona di Foglio.",
              "Modifica e premi ⌘S. Il file resta un `.xlsx`, pronto da rimandare.",
            ],
          },
          {
            heading: "A cosa fare attenzione",
            body: [
              "Foglio non esegue macro, non ha vere tabelle pivot, ignora forme e SmartArt e non apre file protetti da password. Per i fogli di tutti i giorni raramente è un problema, ma conserva l'originale dei file complessi. [LibreOffice Calc](/alternatives/libreoffice/) è un'altra opzione desktop gratuita, più pesante ma con tabelle pivot e macro.",
            ],
          },
        ],
      },
      {
        heading: "3. Usare Apple Numbers",
        body: [
          "Numbers è gratuito ed è spesso già installato. Fai clic destro sul file e scegli **Apri con ▸ Numbers**. Numbers importa la cartella di lavoro e la converte in un documento Numbers; quando hai finito usa **Archivio ▸ Esporta come ▸ Excel** per ottenere di nuovo un `.xlsx`. Se premi solo ⌘S ottieni un file `.numbers`, che chi usa Excel non può aprire.",
          "Per i file semplici funziona bene. Con fogli grandi, alcune formule e la formattazione possono cambiare nel passaggio, e la versione attuale di Numbers richiede macOS 26. I dettagli sono nella pagina [Numbers e Foglio a confronto](/alternatives/numbers/).",
        ],
      },
      {
        heading: "4. Usare il browser: Excel per il web o Fogli Google",
        body: [
          "**Excel per il web** è gratuito con un account Microsoft: carica il file su OneDrive e aprilo nel browser. È il vero Excel, con qualche funzione in meno rispetto alla versione desktop. **Fogli Google** apre i file `.xlsx` caricati su Google Drive, convertendoli oppure modificandoli in modalità di compatibilità Office in Chrome; alla fine scaricali in formato `.xlsx`.",
          "Entrambi richiedono una connessione e un account, ed entrambi significano caricare il file su un servizio cloud. Evita questa strada per i dati riservati, come buste paga o documenti medici. Ne parliamo nella pagina sull'[alternativa a Fogli Google](/alternatives/google-sheets/).",
        ],
      },
      {
        heading: "Rendere la scelta definitiva: l'app predefinita",
        body: [
          "Per aprire sempre i file `.xlsx` con l'app che preferisci, selezionane uno nel Finder, premi ⌘I (Ottieni informazioni), scegli l'app in **Apri con** e fai clic su **Modifica tutto…**.",
        ],
      },
      {
        heading: "Quale soluzione scegliere?",
        body: ["La [pagina di confronto](/compare/) mette tutte le differenze una accanto all'altra."],
        bullets: [
          "**Solo leggere:** Quick Look.",
          "**Modificare e rimandare, in privato e offline:** un'app desktop gratuita come Foglio o LibreOffice.",
          "**Documenti curati per uso personale:** Numbers.",
          "**Lavorare sul file insieme ad altri nello stesso momento:** Excel per il web o Fogli Google.",
        ],
      },
    ],
    faq: [
      {
        q: "Il Mac apre i file xlsx senza programmi aggiuntivi?",
        a: "Puoi vederne l'anteprima con Quick Look (seleziona il file e premi la barra spaziatrice). Per modificarli serve un'app: Numbers è gratuito di Apple, Foglio e LibreOffice si scaricano gratis.",
      },
      {
        q: "Perché il mio file xlsx si apre in Numbers?",
        a: "Su molti Mac Numbers è l'app predefinita per i fogli di calcolo. Puoi cambiarla dal Finder con Ottieni informazioni ▸ Apri con ▸ Modifica tutto….",
      },
      {
        q: "E i file .xlsm con le macro?",
        a: "Le app gratuite aprono i dati, ma solo Excel esegue le macro VBA in modo affidabile. Foglio apre i file `.xlsm` senza eseguire le macro, che non vengono conservate al salvataggio.",
      },
      {
        q: "È sicuro caricare file di lavoro su un visualizzatore online?",
        a: "Dipende dal file e dalle regole della tua azienda. I convertitori e visualizzatori online gratuiti ricevono una copia dei tuoi dati. Un'app desktop tiene il file sul tuo Mac.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Aprire file xlsx senza Excel",
    cardText: "Quick Look, Numbers, un'app desktop gratuita o il browser: quattro modi gratis per aprire e modificare file Excel su Mac.",
  },

  // ───────────────────────────────────────────────────────────────────
  {
    slug: "open-xls-on-mac",
    meta: {
      title: "Come aprire i vecchi file .xls di Excel su Mac | Foglio",
      description:
        "Hai un vecchio file .xls di Excel 97–2003 che Numbers non apre? Come aprirlo gratis su Mac, convertirlo in xlsx e riconoscere i file che non sono veri xls.",
    },
    h1: "Come aprire i vecchi file .xls di Excel su Mac",
    intro: [
      "`.xls` è il formato binario usato da Excel prima del 2007, ed è ancora ovunque: estratti conto, gestionali, dati della pubblica amministrazione, archivi. Le app Mac moderne lo gestiscono peggio dell'`.xlsx`. Numbers, per esempio, può rifiutare alcuni file dicendo che il documento è stato creato con una versione di Excel non supportata.",
      "Ecco come aprire gratis un file `.xls` sul Mac, come convertirlo nel formato moderno `.xlsx` e cosa fare quando il file in realtà non è affatto un `.xls`.",
    ],
    sections: [
      {
        heading: "Soluzione 1: aprirlo con Foglio e salvarlo in xlsx",
        body: [
          "[Foglio](/) è un'app per fogli di calcolo gratuita e open source per Mac. Legge i file `.xls` con calamine, una libreria Rust veloce per i vecchi formati di Excel, e apre anche i file binari `.xlsb`.",
        ],
        bullets: [
          "[Scarica Foglio](/download/) e trascinalo in Applicazioni.",
          "Fai clic destro sul file `.xls` e scegli **Apri con ▸ Foglio** (oppure usa Archivio ▸ Apri in Foglio).",
          "Controlla i dati, poi scegli **Archivio ▸ Salva con nome…** per salvarne una copia `.xlsx`. Foglio non scrive il vecchio formato `.xls`.",
        ],
        sub: [
          {
            heading: "Cosa viene importato",
            body: [
              "Dai file `.xls` e `.xlsb` Foglio importa **valori, formule e date**, su tutti i fogli. La formattazione delle celle, come caratteri, colori e bordi, per ora non viene importata da questi formati, e le macro non vengono mai eseguite. Se ti serve l'aspetto originale di una vecchia cartella, LibreOffice o Excel ne conservano di più.",
            ],
          },
        ],
      },
      {
        heading: "Soluzione 2: LibreOffice Calc",
        body: [
          "LibreOffice Calc è gratuito, open source e gestisce gli `.xls` da decenni, formattazione compresa. Può anche salvare di nuovo in `.xls` se un sistema che usi lo richiede ancora. È un download più pesante (circa 300 MB per Apple silicon) e non è un'app Mac nativa, ma per gli archivi di vecchie cartelle è molto accurato. Vedi [LibreOffice e Foglio a confronto](/alternatives/libreoffice/).",
        ],
      },
      {
        heading: "Soluzione 3: Numbers o Excel",
        body: [
          "Numbers apre molti file `.xls`: clic destro ▸ Apri con ▸ Numbers. Se li rifiuta, convertili prima in `.xlsx` con Foglio o LibreOffice e poi importa quello in Numbers. Microsoft Excel ovviamente apre qualsiasi `.xls`, ma per modificarlo serve un abbonamento o una licenza.",
        ],
      },
      {
        heading: "Quando il “.xls” non è un xls",
        body: [
          "Molti siti e vecchi gestionali esportano file con estensione `.xls` che in realtà sono altro. Se un file mostra etichette strane, tutto in una colonna o testo illeggibile, controlla cosa contiene davvero:",
        ],
        bullets: [
          "**Tabelle HTML.** Alcuni sistemi scrivono una pagina web e la chiamano `.xls`. Aprila con TextEdit: se vedi `<table>` o `<html>`, rinomina la copia in `.html` e aprila nel browser, oppure copia la tabella in un foglio di calcolo.",
          "**Testo separato da tabulazioni o virgole.** Se TextEdit mostra righe di testo semplice, rinomina la copia in `.csv` o `.txt`. Foglio la apre riconoscendo da solo codifica, separatore e virgola decimale; vedi [come aprire file CSV su Mac](/guides/open-csv-on-mac/).",
          "**Un `.xlsx` con l'estensione sbagliata.** Se il file è in realtà un `.xlsx` (in TextEdit inizia con le lettere `PK`), rinomina la copia in `.xlsx`.",
          "**SpreadsheetML (XML).** I file XML di Excel 2003 iniziano con `<?xml` e citano `urn:schemas-microsoft-com:office:spreadsheet`. Foglio non li legge; LibreOffice ed Excel sì.",
        ],
      },
      {
        heading: "Convertire tanti file .xls",
        body: [
          "Foglio converte un file alla volta. Per un archivio grande, LibreOffice può convertire in blocco dal Terminale con l'opzione `--convert-to xlsx`. Qualunque strumento usi, conserva gli `.xls` originali finché non hai controllato i risultati.",
        ],
      },
    ],
    faq: [
      {
        q: "Che differenza c'è tra xls e xlsx?",
        a: "`.xls` è il formato binario di Excel dal 1997 al 2003. `.xlsx` è il formato basato su XML che Excel usa dal 2007: file più piccoli, più robusti e supportati da tutte le app moderne.",
      },
      {
        q: "Foglio può salvare in .xls?",
        a: "No. Foglio apre gli `.xls` e salva in `.xlsx`. Se devi scrivere file `.xls`, usa LibreOffice o Excel.",
      },
      {
        q: "Perché Numbers dice che il file è stato creato con una versione di Excel non supportata?",
        a: "Numbers non importa alcune varianti più vecchie di `.xls`. Apri il file con Foglio o LibreOffice, salvalo in `.xlsx` e Numbers riuscirà a importarlo.",
      },
      {
        q: "I vecchi file xls con le macro sono pericolosi?",
        a: "Le macro possono contenere codice dannoso. Foglio non esegue mai le macro, quindi aprire un `.xls` o un `.xlsm` con Foglio non le avvia. In Excel fai attenzione ad attivare le macro di file che non aspettavi.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Aprire vecchi file .xls su Mac",
    cardText: "Apri gratis i file di Excel 97–2003, convertili in xlsx e riconosci le esportazioni che non sono veri xls.",
  },

  // ───────────────────────────────────────────────────────────────────
  {
    slug: "open-csv-on-mac",
    meta: {
      title: "Aprire file CSV su Mac: colonne e accenti corretti | Foglio",
      description:
        "Il CSV si apre in una sola colonna, con lettere accentate strane o decimali sbagliati? Perché succede su Mac e come aprire i CSV bene, con o senza Excel.",
    },
    h1: "Come aprire i file CSV su Mac (e sistemare colonne, accenti e decimali)",
    intro: [
      "Il CSV sembra il formato più semplice che esista: righe di testo con valori separati da virgole. In pratica è la fonte di infiniti piccoli disastri. Tutto finisce nella colonna A. Le lettere accentate diventano `Ã¨`. Un prezzo di `1,50` diventa `150`. Gli zeri iniziali spariscono dai CAP.",
      "Questa guida spiega le tre cose che vanno storte, come aprire correttamente un CSV sul Mac con o senza Excel e come salvarne uno che gli altri possano aprire.",
    ],
    sections: [
      {
        heading: "Perché i file CSV si aprono male",
        body: [],
        sub: [
          {
            heading: "1. Il separatore",
            body: [
              "Nonostante il nome, molti CSV non sono separati da virgole. Nei paesi che scrivono i decimali con la virgola (Italia, Germania, Francia, Spagna e molti altri) Excel esporta i CSV con il **punto e virgola**. Altri sistemi usano tabulazioni o barre verticali. Se l'app sbaglia separatore, ogni riga finisce in un'unica colonna.",
            ],
          },
          {
            heading: "2. La codifica del testo",
            body: [
              "Un file CSV non dice quale codifica dei caratteri usa. I file moderni sono di solito UTF-8, ma le esportazioni dei vecchi programmi Windows sono spesso Windows-1252, e alcuni strumenti scrivono UTF-16. Letto con la codifica sbagliata, `è` diventa `Ã¨` e `€` diventa un simbolo senza senso.",
            ],
          },
          {
            heading: "3. Il separatore decimale",
            body: [
              "`1,500` in Italia vuol dire uno virgola cinque, negli Stati Uniti millecinquecento. Se l'app legge i numeri con la convenzione del tuo Mac invece che con quella del file, i valori sono sbagliati in silenzio, il che è peggio di un errore visibile.",
            ],
          },
        ],
      },
      {
        heading: "Il modo più semplice: un'app che riconosce tutti e tre",
        body: ["[Foglio](/) è un'app per fogli di calcolo gratuita e open source per Mac che analizza il file prima di importarlo:"],
        bullets: [
          "**Separatore:** sceglie tra virgola, punto e virgola, tabulazione e barra verticale controllando quale divide le prime righe in modo più coerente, ignorando i separatori tra virgolette.",
          "**Codifica:** legge UTF-8 (con o senza BOM) e UTF-16, e ripiega su Windows-1252 per le vecchie esportazioni dell'Europa occidentale.",
          "**Decimali:** capisce se il file scrive `1.234,56` o `1,234.56` e legge ogni numero di conseguenza, qualunque sia la regione del tuo Mac.",
          "**Sicurezza:** il testo che inizia con `=` resta testo e non viene mai eseguito come formula, quindi un CSV malevolo non può avviare calcoli.",
        ],
        sub: [
          {
            heading: "I passaggi",
            body: [
              "[Scarica Foglio](/download/), poi fai clic destro sul file `.csv` e scegli **Apri con ▸ Foglio**. I file `.tsv` e `.txt` funzionano allo stesso modo. Alla fine salvalo come cartella di lavoro Excel (`.xlsx`) per conservare formule e formattazione, oppure di nuovo in CSV.",
            ],
          },
        ],
      },
      {
        heading: "Altri modi per aprire un CSV sul Mac",
        body: [],
        bullets: [
          "**Numbers:** doppio clic o Apri con ▸ Numbers. Funziona bene con i CSV puliti in UTF-8 separati da virgole; con punto e virgola o altre codifiche controlla le impostazioni di importazione e il risultato.",
          "**Excel:** invece del doppio clic usa **Dati ▸ Recupera dati ▸ Da testo/CSV** (o la vecchia importazione guidata da testo), così puoi scegliere separatore, codifica (Origine file) e tipo delle colonne.",
          "**LibreOffice Calc:** mostra una finestra Importa testo in cui scegliere set di caratteri, separatori e tipo di colonna. Molto accurato.",
          "**Fogli Google:** File ▸ Importa ▸ Carica, con riconoscimento automatico o personalizzato del separatore. Richiede di caricare i dati online.",
          "**TextEdit:** non è un foglio di calcolo, ma è utile per vedere cosa c'è davvero nel file.",
        ],
      },
      {
        heading: "Conservare zeri iniziali e numeri lunghi",
        body: [
          "CAP, codici prodotto e numeri di telefono come `00123` sembrano numeri a qualsiasi foglio di calcolo e perdono gli zeri. Gli identificativi lunghi, come numeri di carta o codici simili all'IBAN, vengono arrotondati oltre le 15 cifre. Se queste colonne contano, chiedi un'esportazione con quei valori tra virgolette e con un prefisso, apri il CSV in un'app che permetta di impostare le colonne come Testo durante l'importazione (l'importazione guidata di Excel, LibreOffice), oppure conserva il file originale intatto come riferimento.",
        ],
      },
      {
        heading: "Salvare un CSV che gli altri possano aprire",
        body: [
          "Un CSV contiene solo i valori di un foglio: niente formule, formattazione o altri fogli. Foglio ti avvisa prima di salvare e propone di salvare invece come cartella di lavoro Excel. Quando salvi in CSV, Foglio scrive in UTF-8 con BOM (così Excel riconosce la codifica) e usa il `;` come separatore sui Mac impostati su una regione con la virgola decimale, come fa Excel.",
          "Se il file va a qualcuno in un altro paese, digli quale separatore e quale separatore decimale hai usato, oppure manda un `.xlsx`: eviti tutti i problemi di questa pagina. Per i file Excel, vedi [come aprire file xlsx senza Excel](/guides/open-xlsx-on-mac-without-excel/).",
        ],
      },
    ],
    faq: [
      {
        q: "Perché il mio CSV si apre in una sola colonna?",
        a: "L'app ha usato il separatore sbagliato: di solito il file usa il punto e virgola e l'app si aspettava la virgola, o viceversa. Usa una finestra di importazione per scegliere il separatore, oppure un'app come Foglio che lo riconosce da sola.",
      },
      {
        q: "Come sistemo caratteri strani come Ã¨ in un CSV?",
        a: "Il file è stato letto con la codifica sbagliata, di solito UTF-8 letto come Windows-1252 o viceversa. Riaprilo scegliendo la codifica giusta (quasi sempre UTF-8), oppure con un'app che la riconosce da sola.",
      },
      {
        q: "Come apro un CSV con i punti come decimali su un Mac italiano?",
        a: "Foglio riconosce la convenzione decimale del file e legge `1.5` come uno virgola cinque, qualunque sia la regione del Mac. In Excel usa l'importazione da testo e imposta il separatore decimale nelle opzioni avanzate.",
      },
      {
        q: "Per condividere è meglio CSV o xlsx?",
        a: "L'`.xlsx` conserva formule, formattazione e più fogli, e non ha ambiguità di codifica o separatore. Usa il CSV quando un sistema lo richiede espressamente.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Aprire file CSV su Mac",
    cardText: "Sistema i CSV in una sola colonna, gli accenti illeggibili e le virgole decimali sbagliate, con o senza Excel.",
  },

  // ───────────────────────────────────────────────────────────────────
  {
    slug: "free-spreadsheet-apps-for-mac",
    meta: {
      title: "Fogli di calcolo gratis per Mac a confronto (2026) | Foglio",
      description:
        "I fogli di calcolo gratis per Mac da conoscere nel 2026: Numbers, LibreOffice, Fogli Google, Excel per il web, ONLYOFFICE e Foglio. Per chi è ciascuno.",
    },
    h1: "Fogli di calcolo gratis per Mac: una rassegna onesta",
    intro: [
      "Sul Mac non devi pagare per avere un foglio di calcolo. Esistono diverse opzioni davvero gratuite, e ognuna è brava in qualcosa di diverso. Questa rassegna è scritta dal progetto Foglio, quindi tieni conto del nostro entusiasmo per Foglio; abbiamo cercato di essere onesti su dove le altre sono migliori.",
      "“Gratis” qui significa che puoi creare, modificare e salvare fogli di calcolo senza costi e senza periodi di prova.",
    ],
    sections: [
      {
        heading: "Apple Numbers",
        body: [
          "**Ideale per:** documenti personali belli da vedere e chi usa dispositivi Apple.",
          "Numbers è gratuito, spesso già installato, e funziona su Mac, iPhone e iPad con sincronizzazione iCloud e collaborazione in tempo reale. La tela con tabelle libere e i modelli rendono i documenti curati con poco sforzo. Modelli premium e funzioni di IA richiedono un abbonamento ad Apple Creator Studio, ma l'app di base è gratuita.",
          "**Attenzione:** i file Excel vengono importati e convertiti in `.numbers`, quindi devi esportarli di nuovo in `.xlsx`; la versione attuale richiede macOS 26. Approfondisci in [Numbers e Foglio a confronto](/alternatives/numbers/).",
        ],
      },
      {
        heading: "LibreOffice Calc",
        body: [
          "**Ideale per:** chi vuole il foglio di calcolo desktop gratuito più completo e chi usa OpenDocument.",
          "LibreOffice è open source (MPL-2.0) e funziona su macOS, Windows e Linux. Calc ha tabelle pivot, macro in Basic e Python con supporto parziale a VBA, una libreria di funzioni enorme e un'ottima gestione dei vecchi formati. Funziona offline, senza account e, per scelta, senza funzioni di IA.",
          "**Attenzione:** circa 300 MB da scaricare, un'intera suite da installare e un'interfaccia che su macOS non sembra nativa. Approfondisci in [LibreOffice e Foglio a confronto](/alternatives/libreoffice/).",
        ],
      },
      {
        heading: "Fogli Google",
        body: [
          "**Ideale per:** lavorare sullo stesso foglio insieme ad altre persone.",
          "Fogli Google funziona in qualsiasi browser e sul telefono, con la migliore collaborazione in tempo reale disponibile, cronologia delle versioni, automazioni con Apps Script e funzioni che importano dati dal web.",
          "**Attenzione:** serve un account Google, i file stanno sui server di Google e l'uso offline richiede Chrome o Edge con un'estensione. Approfondisci nell'[alternativa a Fogli Google](/alternatives/google-sheets/).",
        ],
      },
      {
        heading: "Excel per il web",
        body: [
          "**Ideale per:** chi usa Excel ogni tanto e vuole l'originale, gratis.",
          "Microsoft offre Excel nel browser gratuitamente con un account Microsoft. Apre i file `.xlsx` fedelmente, perché è Excel, e permette di lavorare insieme tramite OneDrive.",
          "**Attenzione:** richiede una connessione a Internet e OneDrive, e alcune funzioni della versione desktop (come l'esecuzione delle macro VBA) non sono disponibili. Excel per Mac desktop richiede un abbonamento o una licenza per modificare.",
        ],
      },
      {
        heading: "ONLYOFFICE Desktop Editors",
        body: [
          "**Ideale per:** chi vuole una suite gratuita simile a Office, con la classica barra multifunzione.",
          "ONLYOFFICE Desktop Editors è una suite gratuita e open source (AGPL-3.0) per Mac, Windows e Linux che usa Office Open XML (`.xlsx`) come formato nativo e include un editor di fogli di calcolo con tabelle pivot.",
          "**Attenzione:** è un'app multipiattaforma basata su tecnologie web, quindi il download è più pesante e l'esperienza meno da Mac rispetto a un'app nativa.",
        ],
      },
      {
        heading: "Foglio",
        body: [
          "**Ideale per:** aprire e modificare i file Excel di tutti i giorni in modo rapido, riservato e nativo.",
          "Foglio è gratuito e open source (MIT / Apache-2.0), scritto in Swift/AppKit con un motore in Rust. Pesa 7,5 MB, si apre in 0,24 s, modifica direttamente gli `.xlsx`, conosce circa 500 funzioni di Excel in italiano (`=SOMMA()` su un Mac italiano) e riconosce da solo codifica e separatore dei CSV. Nessun account, nessuna telemetria, nessuna connessione di rete di sua iniziativa.",
          "**Attenzione:** è una versione 1.0; non ha tabelle pivot (solo il più semplice *Riepiloga per*), né macro, né collaborazione, né versioni per iPhone o iPad, e non apre file protetti da password. Vedi il [confronto completo](/compare/).",
        ],
      },
      {
        heading: "In breve: quale app gratuita per quale lavoro",
        body: [],
        bullets: [
          "**Allegati Excel da modificare e rimandare:** Foglio, LibreOffice o Excel per il web.",
          "**Un foglio condiviso in famiglia o nel team:** Fogli Google o Numbers.",
          "**Tabelle pivot o macro, offline e gratis:** LibreOffice Calc.",
          "**Bilanci ed elenchi personali curati:** Numbers.",
          "**Dati riservati che non devono lasciare il Mac:** un'app desktop senza cloud: Foglio, LibreOffice o Numbers con iCloud disattivato per quel file.",
          "**Un Mac non recentissimo:** LibreOffice supporta macOS 11 e Foglio macOS 14; l'ultima versione di Numbers richiede macOS 26.",
        ],
      },
    ],
    faq: [
      {
        q: "Esiste un Excel completamente gratis per Mac?",
        a: "Excel per il web è gratuito con un account Microsoft; Excel per Mac desktop richiede un abbonamento o una licenza per modificare. Tra le app desktop gratuite che aprono e salvano file Excel ci sono Foglio, LibreOffice Calc e ONLYOFFICE.",
      },
      {
        q: "Quale foglio di calcolo gratuito è più compatibile con Excel?",
        a: "Excel per il web, perché è Excel. Tra le app desktop, LibreOffice supporta nel complesso più funzionalità di Excel, mentre Foglio e ONLYOFFICE usano `.xlsx` come formato nativo. Prova i tuoi file: la compatibilità dipende da cosa contengono.",
      },
      {
        q: "Qual è il più leggero?",
        a: "Foglio: 7,5 MB di download e circa 19 MB installato. Fogli Google ed Excel per il web non installano nulla, ma richiedono un browser e una connessione a Internet.",
      },
      {
        q: "Queste app sono gratuite anche per uso aziendale?",
        a: "Foglio (MIT / Apache-2.0), LibreOffice (MPL-2.0) e ONLYOFFICE Desktop Editors (AGPL-3.0) si possono usare al lavoro senza costi. Numbers è gratuito per tutti. Google e Microsoft offrono piani aziendali a pagamento con funzioni aggiuntive.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Fogli di calcolo gratis per Mac",
    cardText: "Numbers, LibreOffice, Fogli Google, Excel per il web, ONLYOFFICE e Foglio: per chi è ciascuno.",
  },

  // ───────────────────────────────────────────────────────────────────
  {
    slug: "excel-functions-italian-english",
    meta: {
      title: "Funzioni di Excel in italiano e inglese: tabella | Foglio",
      description:
        "CERCA.VERT è VLOOKUP, SOMMA è SUM, SE è IF: i nomi delle funzioni di Excel in italiano e inglese, e perché in Italia si usa il punto e virgola.",
    },
    h1: "Le funzioni di Excel in italiano e in inglese",
    intro: [
      "Excel traduce i nomi delle funzioni. Su un Mac in italiano `SUM` è `SOMMA`, `VLOOKUP` è `CERCA.VERT`, `IF` è `SE`, e gli argomenti si separano con il punto e virgola. Comodissimo per chi parla italiano, un po' meno quando segui un tutorial in inglese o lavori con colleghi all'estero.",
      "Qui sotto trovi l'elenco pratico delle funzioni più usate nelle due lingue, seguito dalle regole che mettono più in difficoltà: separatori, virgola decimale e cosa succede quando un file passa da una lingua all'altra.",
    ],
    sections: [
      {
        heading: "Matematica e statistica",
        body: [],
        bullets: pairs(FN_PAIRS, "it-en"),
      },
      {
        heading: "Logica",
        body: [],
        bullets: pairs(LOGIC_PAIRS, "it-en"),
      },
      {
        heading: "Ricerca e matrici dinamiche",
        body: [],
        bullets: pairs(LOOKUP_PAIRS, "it-en"),
      },
      {
        heading: "Testo",
        body: [],
        bullets: pairs(TEXT_PAIRS, "it-en"),
      },
      {
        heading: "Date",
        body: ["Molte funzioni hanno lo stesso nome nelle due lingue, per esempio `MAX`, `MIN`, `LET` e `LAMBDA`."],
        bullets: pairs(DATE_PAIRS, "it-en"),
      },
      {
        heading: "Punto e virgola e virgola decimale",
        body: [
          "In Italia uno e mezzo si scrive `1,5`. Dato che la virgola è già occupata, Excel in italiano separa gli argomenti delle funzioni con il **punto e virgola**: `=SE(A1>1,5;\"sì\";\"no\")` è la forma italiana di `=IF(A1>1.5,\"yes\",\"no\")`. Germania, Francia, Spagna e gran parte dell'Europa continentale funzionano allo stesso modo.",
          "A deciderlo sono le impostazioni della regione del Mac, non solo la lingua: un Mac in inglese con la regione impostata su Italia usa comunque la virgola decimale.",
        ],
      },
      {
        heading: "Ai file non importa in che lingua scrivi",
        body: [
          "Un file `.xlsx` salva sempre le formule in inglese con le virgole: `SUM(A1:A10)`, non `SOMMA`. Ogni copia di Excel le traduce nella lingua del suo utente quando le mostra. Così un collega italiano e uno americano possono condividere lo stesso file senza che nulla si rompa, purché entrambe le app seguano questa regola.",
          "Copiare e incollare il testo di una formula è un'altra storia: incollare `=VLOOKUP(A2,B:C,2,FALSE)` da un sito inglese in Excel in italiano dà errore. Traduci i nomi con l'elenco qui sopra e sostituisci le virgole con il punto e virgola: `=CERCA.VERT(A2;B:C;2;FALSO)`.",
        ],
      },
      {
        heading: "Le formule in italiano in Foglio",
        body: [
          "[Foglio](/), il foglio di calcolo gratuito e open source per Mac, segue la stessa convenzione di Excel. Su un Mac in italiano scrivi `=SOMMA(A1:A10;B2)`, `CERCA.VERT` o `SE.ERRORE` con il punto e virgola e la virgola decimale, con il completamento automatico e le descrizioni in italiano; nel file la formula resta nella forma inglese di Excel. Tedesco (`SUMME`, `SVERWEIS`), spagnolo (`SUMA`, `BUSCARV`) e francese (`SOMME`, `RECHERCHEV`) funzionano allo stesso modo, e la finestra Inserisci funzione elenca tutte le ~500 funzioni con i nomi tradotti.",
          "Anche Fogli Google e LibreOffice traducono i nomi delle funzioni in base alle impostazioni, e così Numbers. Se segui tutorial in inglese, Mostra formule (menu Vista) in Foglio ti aiuta a confrontare quello che hai scritto con quello che mostra il tutorial.",
        ],
      },
    ],
    faq: [
      {
        q: "Come si dice VLOOKUP in Excel in italiano?",
        a: "`CERCA.VERT`. Gli argomenti sono gli stessi, separati dal punto e virgola: `=CERCA.VERT(A2;B:C;2;FALSO)`. XLOOKUP diventa `CERCA.X`.",
      },
      {
        q: "Perché la mia formula dà errore in Excel in italiano?",
        a: "Di solito perché usa i nomi inglesi o le virgole tra gli argomenti. Usa i nomi italiani e il punto e virgola, e scrivi i decimali con la virgola.",
      },
      {
        q: "Posso usare i nomi delle funzioni in inglese?",
        a: "Excel segue la lingua di Office e del sistema. Foglio segue la lingua e la regione del Mac: cambiandole in Impostazioni di Sistema ▸ Generali ▸ Lingua e Zona cambiano anche i nomi delle funzioni.",
      },
      {
        q: "Un file creato con Excel in italiano funziona in Excel in inglese?",
        a: "Sì. Il file salva internamente le formule in inglese, quindi ogni versione di Excel, e anche Foglio, le mostra nella propria lingua.",
      },
    ],
    updated: UPDATED,
    cardTitle: "Funzioni Excel: italiano ↔ inglese",
    cardText: "Circa 50 nomi di funzioni di Excel tradotti, da SOMMA a CERCA.VERT, e perché in Italia si usa il punto e virgola.",
  },
];

export const guides: Record<Locale, Article[]> = { en, it };
