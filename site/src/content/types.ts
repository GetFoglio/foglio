/**
 * Content model for the Foglio website.
 *
 * Every string may use a tiny inline markup that the site renders:
 *   **bold**, `code`, [link text](/internal/path/) or [link text](https://external.example)
 * Internal links are written WITHOUT the locale prefix (e.g. "/compare/"); the site adds "/it" itself.
 * No other Markdown, no HTML.
 */

export type Locale = "en" | "it";
export const locales: Locale[] = ["en", "it"];

/** <title> (≤ 60 characters, the site appends nothing) and meta description (120–155 characters). */
export interface Meta {
  title: string;
  description: string;
  /** Open Graph title, if different from `title`. */
  ogTitle?: string;
}

export interface FAQ {
  q: string;
  a: string;
}

export interface Section {
  /** Rendered as <h2>. */
  heading: string;
  /** Paragraphs. */
  body: string[];
  /** Optional bullet list rendered after the paragraphs. */
  bullets?: string[];
  /** Optional <h3> sub-sections. */
  sub?: { heading: string; body: string[]; bullets?: string[] }[];
}

/** A long-form page: an "alternative to X" landing page or a how-to guide. */
export interface Article {
  /** URL slug, identical in both locales (e.g. "excel-for-mac"). */
  slug: string;
  meta: Meta;
  /** The page's single <h1>. */
  h1: string;
  /** Lead paragraph(s) shown under the h1. */
  intro: string[];
  sections: Section[];
  /** Rendered as an FAQ block + FAQPage JSON-LD. */
  faq?: FAQ[];
  /** ISO date (YYYY-MM-DD) of the last content update. */
  updated: string;
  /** Short label used in cards and navigation (≤ 40 characters). */
  cardTitle: string;
  /** One-sentence teaser used in cards (≤ 140 characters). */
  cardText: string;
}

export interface Feature {
  /** Icon name; one of the keys in src/components/Icon.tsx. */
  icon: "bolt" | "feather" | "gift" | "file" | "function" | "chart" | "globe" | "lock" | "apple" | "code" | "image" | "filter";
  title: string;
  text: string;
}

export interface Step {
  title: string;
  text: string;
}

export interface SiteCopy {
  /** Navigation and shared UI labels. */
  ui: {
    navCompare: string;
    navTechnology: string;
    navAlternatives: string;
    navGuides: string;
    navDownload: string;
    navGitHub: string;
    download: string; // primary button, e.g. "Download for Mac"
    downloadSub: string; // under the button, e.g. "Free · macOS 14+ · Apple silicon & Intel · 7.5 MB"
    viewSource: string; // secondary button
    readMore: string;
    faqTitle: string;
    updated: string; // "Updated" (followed by a date)
    languageName: string; // name of the OTHER language in its own language, e.g. "Italiano" on the English site
    skipToContent: string;
    footerTagline: string;
    footerLicense: string;
    footerTrademark: string; // "Excel is a trademark of Microsoft…; Foglio is not affiliated…"
    notFoundTitle: string;
    notFoundText: string;
    backHome: string;
    yes: string;
    no: string;
    partial: string;
  };

  meta: {
    home: Meta;
    compare: Meta;
    technology: Meta;
    download: Meta;
    alternatives: Meta; // index page of /alternatives/
    guides: Meta; // index page of /guides/
  };

  home: {
    eyebrow: string; // small line above the h1
    h1: string;
    subtitle: string;
    /** Three to four short trust points under the buttons. */
    badges: string[];
    /** Labels for the measured numbers shown in the stats strip (values come from facts.ts). */
    statLabels: {
      download: string;
      launch: string;
      memory: string;
      open100k: string;
      recalc: string;
      price: string;
    };
    featuresTitle: string;
    featuresIntro: string;
    features: Feature[]; // 6 to 9
    speedTitle: string;
    speedIntro: string;
    /** Caption under the bar charts, must say how/where it was measured. */
    speedNote: string;
    freeTitle: string;
    freeText: string[];
    compareTitle: string;
    compareText: string;
    techTitle: string;
    techText: string;
    formatsTitle: string;
    formatsText: string;
    alternativesTitle: string;
    alternativesText: string;
    ctaTitle: string;
    ctaText: string;
    faq: FAQ[]; // 6 to 10, also used for FAQPage JSON-LD
  };

  compare: {
    h1: string;
    intro: string[];
    /** Table headings. */
    tableTitle: string;
    tableNote: string; // how the figures were gathered, with date
    sections: Section[];
    faq: FAQ[];
  };

  technology: {
    h1: string;
    intro: string[];
    sections: Section[];
    faq?: FAQ[];
  };

  download: {
    h1: string;
    intro: string[];
    steps: Step[]; // install steps
    gatekeeperTitle: string;
    gatekeeperText: string[]; // the "unidentified developer" / Open Anyway explanation
    requirementsTitle: string;
    requirements: string[];
    sourceTitle: string;
    sourceText: string[];
    faq: FAQ[];
  };

  /** What Foglio is (and is not) trying to be. Shown on the home and above the comparison table. */
  positioning: {
    title: string;
    text: string[];
    points: { title: string; text: string }[];
  };

  alternativesIndex: { h1: string; intro: string[] };
  guidesIndex: { h1: string; intro: string[] };
}

/** One row of the big comparison table. */
export interface ComparisonRow {
  label: Record<Locale, string>;
  /** Group heading the row belongs to (rows are grouped in the order they appear). */
  group: Record<Locale, string>;
  cells: Record<AppId, ComparisonCell>;
}

export type AppId = "foglio" | "excel" | "numbers" | "libreoffice" | "sheets";

export interface ComparisonCell {
  /** Text shown in the cell. Use a Record when the text differs per language. */
  text: string | Record<Locale, string>;
  /** Colours the cell: good = green check, bad = red cross, partial = amber, neutral = plain. */
  tone: "good" | "bad" | "partial" | "neutral";
}

export interface ComparisonSource {
  label: string;
  url: string;
}
