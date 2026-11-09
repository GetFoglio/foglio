import Link from "next/link";
import { alternatives, comparisonApps, comparisonRows, copy } from "@/content";
import { downloadUrl, facts, site, sizeComparisonMB } from "@/content/facts";
import type { Locale } from "@/content/types";
import { absolute, asset, formatNumber, href } from "@/lib/i18n";
import { Bars, ComparisonTable } from "@/components/Comparison";
import { DownloadButtons, Paragraphs, Positioning, Screenshot } from "@/components/Blocks";
import { Faq } from "@/components/Faq";
import { Icon } from "@/components/Icon";
import { Inline, plain } from "@/components/Inline";
import { JsonLd } from "@/components/JsonLd";
import { Shell } from "@/components/Shell";

const formats = ["xlsx", "xlsm", "xls", "xlsb", "ods", "csv", "tsv", "txt", "pdf"];

export function HomePage({ locale }: { locale: Locale }) {
  const c = copy[locale];
  const h = c.home;
  const n = (x: number) => formatNumber(locale, x);
  const stats = [
    { value: `${n(facts.dmgMB)} MB`, label: h.statLabels.download },
    { value: `${n(facts.launchSeconds)} s`, label: h.statLabels.launch },
    { value: `${n(facts.idleMemoryMB)} MB`, label: h.statLabels.memory },
    { value: locale === "en" ? "$0" : "0 €", label: h.statLabels.price },
  ];
  const sizes = [
    { label: comparisonApps.foglio.name, value: sizeComparisonMB.foglio, highlight: true },
    { label: comparisonApps.libreoffice.name, value: sizeComparisonMB.libreoffice },
    { label: comparisonApps.numbers.name, value: sizeComparisonMB.numbers },
    { label: comparisonApps.excel.name, value: sizeComparisonMB.excel },
  ].map((s) => ({ ...s, display: s.value >= 1000 ? `${n(s.value / 1000)} GB` : `${n(s.value)} MB` }));
  const ui = homeUi[locale];
  const speedup = Math.round(facts.vlookupBeforeMs / facts.vlookupAfterMs / 100) * 100;
  const metrics = [
    { value: `${n(facts.open100kSeconds)} s`, label: h.statLabels.open100k },
    { value: `${n(facts.editMs)} ms`, label: h.statLabels.recalc },
    {
      value: `${n(facts.vlookupAfterMs)} ms`,
      label: ui.lookupTitle,
      sub: ui.lookupSub(n(Math.round(facts.vlookupBeforeMs / 100) / 10), new Intl.NumberFormat(locale === "en" ? "en-US" : "it-IT", { useGrouping: "always" }).format(speedup)),
    },
  ];
  // Fewer, distinct features: speed, size and privacy have their own sections.
  const shown = new Set(["file", "function", "globe", "apple", "chart", "filter"]);
  const features = h.features.filter((f) => shown.has(f.icon)).slice(0, 6);
  const teaserRows = comparisonRows.slice(0, 6);

  return (
    <Shell locale={locale} path="/">
      <section className="hero">
        <div className="wrap hero-grid">
          <div className="hero-copy">
            <p className="eyebrow">{h.eyebrow}</p>
            <h1>{h.h1}</h1>
            <p className="lead">
              <Inline text={h.subtitle} locale={locale} />
            </p>
            <DownloadButtons locale={locale} />
            <ul className="badges">
              {h.badges.slice(0, 3).map((b) => (
                <li key={b}>
                  <Icon name="check" size={16} />
                  {b}
                </li>
              ))}
            </ul>
          </div>
        </div>
        <div className="wrap">
          <Screenshot locale={locale} alt={plain(h.h1)} priority />
        </div>
      </section>

      <section className="stats">
        <div className="wrap stats-grid">
          {stats.map((s) => (
            <div key={s.label} className="stat">
              <span className="stat-value">{s.value}</span>
              <span className="stat-label">{s.label}</span>
            </div>
          ))}
        </div>
      </section>

      <section className="section" aria-labelledby="features">
        <div className="wrap">
          <div className="section-head">
            <h2 id="features">{h.featuresTitle}</h2>
            <p className="lead">
              <Inline text={h.featuresIntro} locale={locale} />
            </p>
          </div>
          <div className="cards">
            {features.map((f) => (
              <article key={f.title} className="card">
                <span className="card-icon">
                  <Icon name={f.icon} size={22} />
                </span>
                <h3>{f.title}</h3>
                <p>
                  <Inline text={f.text} locale={locale} />
                </p>
              </article>
            ))}
          </div>
          <div className="formats">
            <span className="muted small">{ui.opens}</span>
            <ul className="chips">
              {formats.map((f) => (
                <li key={f}>.{f}</li>
              ))}
            </ul>
          </div>
        </div>
      </section>

      <section className="section alt" aria-labelledby="speed">
        <div className="wrap">
          <div className="section-head">
            <h2 id="speed">{h.speedTitle}</h2>
            <p className="lead">
              <Inline text={h.speedIntro} locale={locale} />
            </p>
          </div>
          <div className="two-col">
            <Bars title={h.statLabels.download} unit={ui.lower} items={sizes} />
            <ul className="metrics">
              {metrics.map((m) => (
                <li key={m.label}>
                  <span className="metric-value">{m.value}</span>
                  <span className="metric-label">
                    {m.label}
                    {m.sub && <span className="metric-sub">{m.sub}</span>}
                  </span>
                </li>
              ))}
            </ul>
          </div>
          <p className="muted small center">{ui.tested}</p>
        </div>
      </section>

      <section className="section" aria-labelledby="free">
        <div className="wrap two-col align-center">
          <div>
            <h2 id="free">{h.freeTitle}</h2>
            <Paragraphs items={h.freeText} locale={locale} />
            <DownloadButtons locale={locale} />
          </div>
          <div className="price-card" aria-hidden="true">
            <span className="price">{locale === "en" ? "$0" : "0 €"}</span>
            <span className="muted">{c.ui.downloadSub}</span>
            <span className="license">{site.license}</span>
          </div>
        </div>
      </section>

      <section className="section alt" aria-labelledby="goal">
        <div className="wrap">
          <Positioning locale={locale} />
        </div>
      </section>

      <section className="section" aria-labelledby="compare">
        <div className="wrap">
          <div className="section-head">
            <h2 id="compare">{h.compareTitle}</h2>
            <p className="lead">
              <Inline text={h.compareText} locale={locale} />
            </p>
          </div>
          {teaserRows.length > 0 && <ComparisonTable locale={locale} rows={teaserRows} caption={h.compareTitle} />}
          <p className="center">
            <Link className="btn btn-ghost" href={href(locale, "/compare/")}>
              {c.ui.navCompare}
              <Icon name="arrow" size={16} />
            </Link>
          </p>
        </div>
      </section>

      <section className="section alt" aria-labelledby="tech">
        <div className="wrap two-col align-center">
          <div>
            <h2 id="tech">{h.techTitle}</h2>
            <p>
              <Inline text={h.techText} locale={locale} />
            </p>
            <Link className="text-link" href={href(locale, "/technology/")}>
              {c.ui.readMore} <Icon name="arrow" size={16} />
            </Link>
          </div>
          <Architecture locale={locale} />
        </div>
      </section>

      {alternatives[locale].length > 0 && (
        <section className="section" aria-labelledby="alternatives">
          <div className="wrap">
            <div className="section-head">
              <h2 id="alternatives">{h.alternativesTitle}</h2>
              <p className="lead">
                <Inline text={h.alternativesText} locale={locale} />
              </p>
            </div>
            <div className="cards cards-4">
              {alternatives[locale].map((a) => (
                <Link key={a.slug} className="card card-link" href={href(locale, `/alternatives/${a.slug}/`)}>
                  <h3>{a.cardTitle}</h3>
                  <p>{a.cardText}</p>
                  <span className="text-link">
                    {c.ui.readMore} <Icon name="arrow" size={16} />
                  </span>
                </Link>
              ))}
            </div>
          </div>
        </section>
      )}

      <Faq items={h.faq} title={c.ui.faqTitle} locale={locale} />

      <section className="section final-cta">
        <div className="wrap narrow center">
          <img src={asset("/icon-192.webp")} width={96} height={96} alt="" loading="lazy" />
          <h2>{h.ctaTitle}</h2>
          <p className="lead">
            <Inline text={h.ctaText} locale={locale} />
          </p>
          <DownloadButtons locale={locale} center />
        </div>
      </section>

      <JsonLd
        data={{
          "@context": "https://schema.org",
          "@graph": [
            {
              "@type": "SoftwareApplication",
              "@id": `${site.url}/#app`,
              name: site.name,
              description: c.meta.home.description,
              url: absolute(locale, "/"),
              applicationCategory: "BusinessApplication",
              applicationSubCategory: "Spreadsheet",
              operatingSystem: `macOS ${site.minMacOS} or later`,
              softwareVersion: site.version,
              datePublished: site.released,
              downloadUrl,
              fileSize: `${facts.dmgMB}MB`,
              license: "https://opensource.org/licenses/MIT",
              isAccessibleForFree: true,
              inLanguage: ["en", "it"],
              image: `${site.url}/icon-256.png`,
              screenshot: `${site.url}/screenshots/${locale}-light.webp`,
              offers: { "@type": "Offer", price: "0", priceCurrency: locale === "en" ? "USD" : "EUR" },
              codeRepository: site.repo,
            },
            {
              "@type": "WebSite",
              "@id": `${site.url}/#website`,
              name: site.name,
              url: site.url,
              inLanguage: locale,
            },
          ],
        }}
      />
    </Shell>
  );
}

const homeUi: Record<
  Locale,
  {
    lower: string;
    lookupTitle: string;
    lookupSub: (before: string, times: string) => string;
    tested: string;
    opens: string;
    arch: [string, string, string, string];
  }
> = {
  en: {
    lower: "smaller is better",
    lookupTitle: "1,000 VLOOKUPs over 10,000 rows",
    lookupSub: (before, times) => `${before} seconds in the original engine: about ${times}× faster`,
    tested: "Tested on a Mac with an M4 processor, macOS 27.",
    opens: "Opens",
    arch: [
      "Windows, menus, documents and a custom grid view drawn with AppKit",
      "Rust core",
      "Workbook model, IronCalc formula engine (patched fork), xlsx / xls / ods / csv",
      "Architecture: a Swift/AppKit app calls a Rust core through a plain C interface",
    ],
  },
  it: {
    lower: "più piccolo è meglio",
    lookupTitle: "1.000 CERCA.VERT su 10.000 righe",
    lookupSub: (before, times) => `${before} secondi nel motore originale: circa ${times} volte più veloce`,
    tested: "Testato su un Mac con processore M4, macOS 27.",
    opens: "Apre",
    arch: [
      "Finestre, menu, documenti e una griglia su misura disegnata con AppKit",
      "Nucleo in Rust",
      "Modello della cartella, motore di formule IronCalc (fork con patch), xlsx / xls / ods / csv",
      "Architettura: un'app Swift/AppKit chiama un nucleo in Rust tramite una semplice interfaccia C",
    ],
  },
};

function Architecture({ locale }: { locale: Locale }) {
  const [app, core, coreText, label] = homeUi[locale].arch;
  return (
    <figure className="arch" aria-label={label}>
      <div className="arch-box">
        <strong>Swift · AppKit</strong>
        <span>{app}</span>
      </div>
      <div className="arch-link">C ABI</div>
      <div className="arch-box rust">
        <strong>{core}</strong>
        <span>{coreText}</span>
      </div>
    </figure>
  );
}
