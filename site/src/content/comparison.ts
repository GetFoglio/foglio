import type { AppId, ComparisonRow, ComparisonSource, Locale } from "./types";

export const comparisonApps: Record<AppId, { name: string; maker: string }> = {
  foglio: { name: "Foglio", maker: "Open source" },
  excel: { name: "Microsoft Excel", maker: "Microsoft" },
  numbers: { name: "Apple Numbers", maker: "Apple" },
  libreoffice: { name: "LibreOffice Calc", maker: "The Document Foundation" },
  sheets: { name: "Google Sheets", maker: "Google" },
};

const G = {
  price: { en: "Price & license", it: "Prezzo e licenza" },
  size: { en: "Size & speed", it: "Dimensioni e velocità" },
  platform: { en: "Platform", it: "Piattaforma" },
  formats: { en: "File formats", it: "Formati di file" },
  features: { en: "Features", it: "Funzionalità" },
  privacy: { en: "Privacy", it: "Privacy" },
} satisfies Record<string, Record<Locale, string>>;

const t = (en: string, it: string) => ({ en, it });

export const comparisonRows: ComparisonRow[] = [
  // ── Price & license ───────────────────────────────────────────────
  {
    group: G.price,
    label: t("Price", "Prezzo"),
    cells: {
      foglio: { text: t("Free", "Gratis"), tone: "good" },
      excel: {
        text: t(
          "Microsoft 365 Personal $99.99/yr, Family $129.99/yr, or Office Home 2024 $179.99 one-time",
          "Microsoft 365 Personal 99 €/anno, Family 129 €/anno, oppure Office Home 2024 149 € una tantum",
        ),
        tone: "bad",
      },
      numbers: {
        text: t(
          "Free; optional Apple Creator Studio ($12.99/mo) for premium templates and AI",
          "Gratis; Apple Creator Studio facoltativo (12,99 €/mese o 129 €/anno) per modelli premium e IA",
        ),
        tone: "good",
      },
      libreoffice: { text: t("Free", "Gratis"), tone: "good" },
      sheets: {
        text: t("Free with a Google account; paid Workspace plans for business", "Gratis con account Google; piani Workspace a pagamento per le aziende"),
        tone: "good",
      },
    },
  },
  {
    group: G.price,
    label: t("Open source", "Open source"),
    cells: {
      foglio: { text: "MIT / Apache-2.0", tone: "good" },
      excel: { text: t("No", "No"), tone: "bad" },
      numbers: { text: t("No", "No"), tone: "bad" },
      libreoffice: { text: "MPL-2.0", tone: "good" },
      sheets: { text: t("No", "No"), tone: "bad" },
    },
  },
  {
    group: G.price,
    label: t("Account needed", "Account richiesto"),
    cells: {
      foglio: { text: t("No", "No"), tone: "good" },
      excel: {
        text: t("Microsoft account and a subscription or license to edit", "Account Microsoft e abbonamento o licenza per modificare"),
        tone: "bad",
      },
      numbers: {
        text: t("No (Apple Account only for iCloud sharing)", "No (Apple Account solo per la condivisione iCloud)"),
        tone: "good",
      },
      libreoffice: { text: t("No", "No"), tone: "good" },
      sheets: { text: t("Google account required", "Account Google obbligatorio"), tone: "bad" },
    },
  },

  // ── Size & speed ──────────────────────────────────────────────────
  {
    group: G.size,
    label: t("Download size", "Dimensione del download"),
    cells: {
      foglio: { text: t("7.5 MB (universal)", "7,5 MB (universale)"), tone: "good" },
      excel: { text: t("1.2 GB (Excel alone, Mac App Store)", "1,2 GB (solo Excel, Mac App Store)"), tone: "bad" },
      numbers: { text: t("661 MB (App Store listing)", "661 MB (scheda App Store)"), tone: "bad" },
      libreoffice: { text: t("≈ 300 MB (Apple silicon disk image)", "≈ 300 MB (immagine disco Apple silicon)"), tone: "partial" },
      sheets: { text: t("Nothing to install (runs in a browser)", "Niente da installare (funziona nel browser)"), tone: "neutral" },
    },
  },
  {
    group: G.size,
    label: t("Disk space", "Spazio su disco"),
    cells: {
      foglio: { text: "19 MB", tone: "good" },
      excel: { text: t("Over 1 GB", "Oltre 1 GB"), tone: "bad" },
      numbers: { text: t("Hundreds of MB", "Centinaia di MB"), tone: "partial" },
      libreoffice: { text: t("Up to 800 MB (official requirements)", "Fino a 800 MB (requisiti ufficiali)"), tone: "partial" },
      sheets: { text: t("Browser cache only", "Solo cache del browser"), tone: "neutral" },
    },
  },
  {
    group: G.size,
    label: t("What it is built with", "Com'è costruito"),
    cells: {
      foglio: { text: t("Swift/AppKit + Rust, no bundled runtime", "Swift/AppKit + Rust, nessun runtime incluso"), tone: "good" },
      excel: { text: t("Native Mac app (Microsoft Office codebase)", "App Mac nativa (codice di Microsoft Office)"), tone: "good" },
      numbers: { text: t("Native Mac app", "App Mac nativa"), tone: "good" },
      libreoffice: {
        text: t("Cross-platform C++ suite with its own UI toolkit", "Suite multipiattaforma in C++ con un proprio toolkit grafico"),
        tone: "partial",
      },
      sheets: { text: t("Web app", "Applicazione web"), tone: "partial" },
    },
  },

  // ── Platform ──────────────────────────────────────────────────────
  {
    group: G.platform,
    label: t("Minimum macOS", "macOS minimo"),
    cells: {
      foglio: { text: "macOS 14", tone: "good" },
      excel: { text: "macOS 14", tone: "good" },
      numbers: {
        text: t("macOS 26 for the current version", "macOS 26 per la versione attuale"),
        tone: "partial",
      },
      libreoffice: { text: "macOS 11", tone: "good" },
      sheets: { text: t("Any recent browser", "Qualsiasi browser recente"), tone: "good" },
    },
  },
  {
    group: G.platform,
    label: t("Apple silicon and Intel", "Apple silicon e Intel"),
    cells: {
      foglio: { text: t("Yes, one universal app", "Sì, un'unica app universale"), tone: "good" },
      excel: { text: t("Yes", "Sì"), tone: "good" },
      numbers: { text: t("Yes", "Sì"), tone: "good" },
      libreoffice: { text: t("Yes, separate downloads", "Sì, download separati"), tone: "good" },
      sheets: { text: t("Yes (browser)", "Sì (browser)"), tone: "good" },
    },
  },
  {
    group: G.platform,
    label: t("Works fully offline", "Funziona offline"),
    cells: {
      foglio: { text: t("Yes", "Sì"), tone: "good" },
      excel: { text: t("Yes (subscription checked online periodically)", "Sì (abbonamento verificato periodicamente online)"), tone: "good" },
      numbers: { text: t("Yes", "Sì"), tone: "good" },
      libreoffice: { text: t("Yes", "Sì"), tone: "good" },
      sheets: {
        text: t("Partly: Chrome or Edge with an extension, set up while online", "In parte: Chrome o Edge con un'estensione, da attivare quando sei online"),
        tone: "partial",
      },
    },
  },
  {
    group: G.platform,
    label: t("Windows and Linux", "Windows e Linux"),
    cells: {
      foglio: { text: t("No, Mac only", "No, solo Mac"), tone: "bad" },
      excel: { text: t("Windows (and the web)", "Windows (e web)"), tone: "good" },
      numbers: { text: t("No (iCloud web only)", "No (solo iCloud sul web)"), tone: "partial" },
      libreoffice: { text: t("Windows and Linux", "Windows e Linux"), tone: "good" },
      sheets: { text: t("Any browser", "Qualsiasi browser"), tone: "good" },
    },
  },
  {
    group: G.platform,
    label: t("iPhone and iPad apps", "App per iPhone e iPad"),
    cells: {
      foglio: { text: t("No", "No"), tone: "bad" },
      excel: { text: t("Yes", "Sì"), tone: "good" },
      numbers: { text: t("Yes", "Sì"), tone: "good" },
      libreoffice: { text: t("No", "No"), tone: "bad" },
      sheets: { text: t("Yes", "Sì"), tone: "good" },
    },
  },

  // ── File formats ──────────────────────────────────────────────────
  {
    group: G.formats,
    label: t("Edits .xlsx directly", "Modifica direttamente i file .xlsx"),
    cells: {
      foglio: { text: t("Yes, opens and saves .xlsx", "Sì, apre e salva .xlsx"), tone: "good" },
      excel: { text: t("Yes (the reference)", "Sì (il riferimento)"), tone: "good" },
      numbers: {
        text: t("Converts to .numbers; exports back to .xlsx", "Converte in .numbers; esporta di nuovo in .xlsx"),
        tone: "partial",
      },
      libreoffice: { text: t("Yes", "Sì"), tone: "good" },
      sheets: {
        text: t("Converts, or Office editing mode in Chrome", "Converte, oppure modalità di compatibilità Office in Chrome"),
        tone: "partial",
      },
    },
  },
  {
    group: G.formats,
    label: t("Old .xls files", "Vecchi file .xls"),
    cells: {
      foglio: {
        text: t("Opens values, formulas and dates; saves as .xlsx", "Apre valori, formule e date; salva in .xlsx"),
        tone: "partial",
      },
      excel: { text: t("Opens and saves", "Apre e salva"), tone: "good" },
      numbers: { text: t("Opens most; very old versions refused", "Apre la maggior parte; rifiuta le versioni molto vecchie"), tone: "partial" },
      libreoffice: { text: t("Opens and saves", "Apre e salva"), tone: "good" },
      sheets: { text: t("Imports", "Importa"), tone: "good" },
    },
  },
  {
    group: G.formats,
    label: t("OpenDocument .ods", "OpenDocument .ods"),
    cells: {
      foglio: { text: t("Opens values, formulas and dates", "Apre valori, formule e date"), tone: "partial" },
      excel: { text: t("Opens and saves", "Apre e salva"), tone: "good" },
      numbers: { text: t("No", "No"), tone: "bad" },
      libreoffice: { text: t("Native format", "Formato nativo"), tone: "good" },
      sheets: { text: t("Imports and exports", "Importa ed esporta"), tone: "good" },
    },
  },
  {
    group: G.formats,
    label: t("CSV with any encoding or delimiter", "CSV con qualsiasi codifica o separatore"),
    cells: {
      foglio: { text: t("Detected automatically", "Rilevati automaticamente"), tone: "good" },
      excel: { text: t("Import wizard / Power Query", "Procedura di importazione / Power Query"), tone: "good" },
      numbers: { text: t("Basic import settings", "Impostazioni di importazione di base"), tone: "partial" },
      libreoffice: { text: t("Text Import dialog", "Finestra Importa testo"), tone: "good" },
      sheets: { text: t("Import with separator detection", "Importazione con rilevamento del separatore"), tone: "good" },
    },
  },
  {
    group: G.formats,
    label: t("Password-protected files", "File protetti da password"),
    cells: {
      foglio: { text: t("Not supported", "Non supportati"), tone: "bad" },
      excel: { text: t("Yes", "Sì"), tone: "good" },
      numbers: { text: t("Yes", "Sì"), tone: "good" },
      libreoffice: { text: t("Yes", "Sì"), tone: "good" },
      sheets: { text: t(".xlsx only", "Solo .xlsx"), tone: "partial" },
    },
  },

  // ── Features ──────────────────────────────────────────────────────
  {
    group: G.features,
    label: t("Modern functions (XLOOKUP, FILTER, LET, LAMBDA)", "Funzioni moderne (CERCA.X, FILTRO, LET, LAMBDA)"),
    cells: {
      foglio: { text: t("Yes, ~500 functions", "Sì, ~500 funzioni"), tone: "good" },
      excel: { text: t("Yes", "Sì"), tone: "good" },
      numbers: { text: t("Yes, LAMBDA with limits", "Sì, LAMBDA con limitazioni"), tone: "good" },
      libreoffice: { text: t("XLOOKUP, FILTER, LET; no LAMBDA", "CERCA.X, FILTRO, LET; niente LAMBDA"), tone: "partial" },
      sheets: { text: t("Yes", "Sì"), tone: "good" },
    },
  },
  {
    group: G.features,
    label: t("Formulas in your language", "Formule nella tua lingua"),
    cells: {
      foglio: { text: t("Italian, German, Spanish, French, English", "Italiano, tedesco, spagnolo, francese, inglese"), tone: "good" },
      excel: { text: t("Yes, many languages", "Sì, molte lingue"), tone: "good" },
      numbers: { text: t("Yes", "Sì"), tone: "good" },
      libreoffice: { text: t("Yes, many languages", "Sì, molte lingue"), tone: "good" },
      sheets: { text: t("Yes, by spreadsheet locale", "Sì, in base alle impostazioni locali del foglio"), tone: "good" },
    },
  },
  {
    group: G.features,
    label: t("Pivot tables", "Tabelle pivot"),
    cells: {
      foglio: {
        text: t("No; “Summarize by” builds a simple live summary", "No; “Riepiloga per” crea un semplice riepilogo dinamico"),
        tone: "bad",
      },
      excel: { text: t("Yes, the most complete", "Sì, le più complete"), tone: "good" },
      numbers: { text: t("Yes", "Sì"), tone: "good" },
      libreoffice: { text: t("Yes", "Sì"), tone: "good" },
      sheets: { text: t("Yes", "Sì"), tone: "good" },
    },
  },
  {
    group: G.features,
    label: t("Macros and scripting", "Macro e script"),
    cells: {
      foglio: { text: t("No (.xlsm opens, macros are not run)", "No (i file .xlsm si aprono, le macro non vengono eseguite)"), tone: "bad" },
      excel: { text: t("VBA, Office Scripts", "VBA, Office Scripts"), tone: "good" },
      numbers: { text: t("No (AppleScript and Shortcuts only)", "No (solo AppleScript e Comandi rapidi)"), tone: "bad" },
      libreoffice: { text: t("Basic, Python; partial VBA", "Basic, Python; VBA in parte"), tone: "good" },
      sheets: { text: t("Apps Script (no VBA)", "Apps Script (niente VBA)"), tone: "partial" },
    },
  },
  {
    group: G.features,
    label: t("Charts", "Grafici"),
    cells: {
      foglio: {
        text: t("Column, bar, line, pie, doughnut, area, scatter", "Colonne, barre, linee, torta, anello, area, dispersione"),
        tone: "partial",
      },
      excel: { text: t("Widest range", "La gamma più ampia"), tone: "good" },
      numbers: { text: t("Wide range, interactive charts", "Ampia gamma, grafici interattivi"), tone: "good" },
      libreoffice: { text: t("Wide range", "Ampia gamma"), tone: "good" },
      sheets: { text: t("Wide range", "Ampia gamma"), tone: "good" },
    },
  },
  {
    group: G.features,
    label: t("Conditional formatting", "Formattazione condizionale"),
    cells: {
      foglio: { text: t("Rules and color scales; no data bars or icon sets", "Regole e scale di colori; niente barre dei dati o set di icone"), tone: "partial" },
      excel: { text: t("Yes", "Sì"), tone: "good" },
      numbers: { text: t("Yes", "Sì"), tone: "good" },
      libreoffice: { text: t("Yes", "Sì"), tone: "good" },
      sheets: { text: t("Yes", "Sì"), tone: "good" },
    },
  },
  {
    group: G.features,
    label: t("Real-time collaboration", "Collaborazione in tempo reale"),
    cells: {
      foglio: { text: t("No", "No"), tone: "bad" },
      excel: { text: t("Yes, via OneDrive or SharePoint", "Sì, tramite OneDrive o SharePoint"), tone: "good" },
      numbers: { text: t("Yes, via iCloud", "Sì, tramite iCloud"), tone: "good" },
      libreoffice: { text: t("No (desktop app)", "No (app desktop)"), tone: "bad" },
      sheets: { text: t("Yes, the best at it", "Sì, il migliore in questo"), tone: "good" },
    },
  },
  {
    group: G.features,
    label: t("AI assistant", "Assistente IA"),
    cells: {
      foglio: { text: t("None", "Nessuno"), tone: "neutral" },
      excel: { text: t("Copilot, in Microsoft 365 Personal and Family", "Copilot, in Microsoft 365 Personal e Family"), tone: "good" },
      numbers: {
        text: t("Apple Intelligence; assistant with Creator Studio", "Apple Intelligence; assistente con Creator Studio"),
        tone: "partial",
      },
      libreoffice: { text: t("None, by design", "Nessuno, per scelta"), tone: "neutral" },
      sheets: { text: t("Gemini, depending on plan", "Gemini, a seconda del piano"), tone: "partial" },
    },
  },

  // ── Privacy ───────────────────────────────────────────────────────
  {
    group: G.privacy,
    label: t("Where your files live", "Dove stanno i tuoi file"),
    cells: {
      foglio: { text: t("On your Mac", "Sul tuo Mac"), tone: "good" },
      excel: { text: t("Your Mac or OneDrive", "Sul Mac o su OneDrive"), tone: "good" },
      numbers: { text: t("Your Mac or iCloud", "Sul Mac o su iCloud"), tone: "good" },
      libreoffice: { text: t("On your Mac", "Sul tuo Mac"), tone: "good" },
      sheets: { text: t("Google's servers", "Sui server di Google"), tone: "partial" },
    },
  },
  {
    group: G.privacy,
    label: t("Telemetry", "Telemetria"),
    cells: {
      foglio: { text: t("None; no network connections", "Nessuna; nessuna connessione di rete"), tone: "good" },
      excel: {
        text: t("Required diagnostic data; optional data can be turned off", "Dati di diagnostica obbligatori; quelli facoltativi si possono disattivare"),
        tone: "partial",
      },
      numbers: { text: t("Usage and diagnostics (App Store privacy label)", "Dati di utilizzo e diagnostica (etichetta privacy dell'App Store)"), tone: "partial" },
      libreoffice: { text: t("None; update check can be turned off", "Nessuna; il controllo aggiornamenti si può disattivare"), tone: "good" },
      sheets: { text: t("Usage data as per Google's privacy policy", "Dati di utilizzo secondo l'informativa privacy di Google"), tone: "partial" },
    },
  },
];

export const comparisonSources: ComparisonSource[] = [
  {
    label: "Microsoft: compare Microsoft 365 plans and Office Home 2024 (US prices)",
    url: "https://www.microsoft.com/en-us/microsoft-365/buy/compare-all-microsoft-365-products",
  },
  {
    label: "Microsoft Italia: confronta i piani Microsoft 365 e Office Home 2024 (prezzi in euro)",
    url: "https://www.microsoft.com/it-it/microsoft-365/buy/compare-all-microsoft-365-products",
  },
  {
    label: "Telefonino.net: Apple Creator Studio in Italia, 12,99 €/mese o 129 €/anno",
    url: "https://www.telefonino.net/notizie/apple-creator-studio-la-rivoluzione-creativa-parte-da-1299-euro-al-mese/",
  },
  {
    label: "Mac App Store: Microsoft Excel (size, requirements, in-app purchases)",
    url: "https://apps.apple.com/us/app/microsoft-excel/id462058435?mt=12",
  },
  {
    label: "Microsoft Learn: required diagnostic data for Microsoft 365 Apps",
    url: "https://learn.microsoft.com/en-us/microsoft-365-apps/privacy/required-diagnostic-data",
  },
  {
    label: "App Store: Numbers (size, requirements, Creator Studio, privacy label)",
    url: "https://apps.apple.com/us/app/numbers-make-spreadsheets/id361304891",
  },
  {
    label: "Apple Support: About Apple Creator Studio",
    url: "https://support.apple.com/en-ca/125029",
  },
  {
    label: "Apple Support: Numbers Formulas and Functions Help",
    url: "https://support.apple.com/guide/functions",
  },
  {
    label: "LibreOffice: download page (version 26.8.2, Apple silicon and Intel builds)",
    url: "https://www.libreoffice.org/download/download-libreoffice/",
  },
  {
    label: "LibreOffice: system requirements (macOS 11+, up to 800 MB)",
    url: "https://www.libreoffice.org/get-help/system-requirements/",
  },
  {
    label: "LibreOffice Bugzilla: LAMBDA function request (tdf#138749)",
    url: "https://www.libreoffice.org/bugzilla/show_bug.cgi?id=138749",
  },
  {
    label: "It's FOSS: LibreOffice 26.8 and its no-AI stance",
    url: "https://itsfoss.com/news/libreoffice-26-8-release/",
  },
  {
    label: "Google Docs Editors Help: use Google Docs, Sheets and Slides offline",
    url: "https://support.google.com/docs/answer/6388102?hl=en",
  },
  {
    label: "Google Docs Editors Help: work with Office files (macros, passwords)",
    url: "https://support.google.com/docs/answer/6055139?hl=en",
  },
  {
    label: "Google Drive Help: file size limits (Sheets)",
    url: "https://support.google.com/docs/answer/37603?hl=en",
  },
  {
    label: "Foglio README: features, formats and limitations",
    url: "https://github.com/Acid236/foglio#readme",
  },
];

export const comparisonChecked = "2026-11-09";
