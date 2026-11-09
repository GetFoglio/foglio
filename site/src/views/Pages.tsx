import Link from "next/link";
import { notFound } from "next/navigation";
import { alternatives, comparisonChecked, comparisonSources, copy, guides } from "@/content";
import { downloadUrl, facts, releasesUrl, site } from "@/content/facts";
import type { Article, Locale } from "@/content/types";
import { absolute, formatDate, href } from "@/lib/i18n";
import { Breadcrumbs, DownloadButtons, PageHero, Paragraphs, Positioning, Prose, Screenshot } from "@/components/Blocks";
import { ComparisonTable } from "@/components/Comparison";
import { Faq } from "@/components/Faq";
import { Icon } from "@/components/Icon";
import { Inline, plain } from "@/components/Inline";
import { JsonLd } from "@/components/JsonLd";
import { Shell } from "@/components/Shell";

export function ComparePage({ locale }: { locale: Locale }) {
  const c = copy[locale];
  const p = c.compare;
  return (
    <Shell locale={locale} path="/compare/">
      <PageHero locale={locale} h1={p.h1} intro={p.intro} trail={[{ name: c.ui.navCompare, path: "/compare/" }]} />
      <div className="wrap">
        <Positioning locale={locale} />
        <h2 className="table-title">{p.tableTitle}</h2>
        <ComparisonTable locale={locale} caption={p.tableTitle} />
        <p className="muted small">
          <Inline text={p.tableNote} locale={locale} /> ({formatDate(locale, comparisonChecked)})
        </p>
        {comparisonSources.length > 0 && (
          <details className="sources">
            <summary>{locale === "en" ? "Sources" : "Fonti"}</summary>
            <ul>
              {comparisonSources.map((s) => (
                <li key={s.url}>
                  <a href={s.url} rel="noopener nofollow" target="_blank">
                    {s.label}
                  </a>
                </li>
              ))}
            </ul>
          </details>
        )}
      </div>
      <article className="wrap narrow prose">
        <Prose sections={p.sections} locale={locale} />
      </article>
      <Faq items={p.faq} title={c.ui.faqTitle} locale={locale} />
      <CtaBand locale={locale} />
    </Shell>
  );
}

export function TechnologyPage({ locale }: { locale: Locale }) {
  const c = copy[locale];
  const p = c.technology;
  return (
    <Shell locale={locale} path="/technology/">
      <PageHero locale={locale} h1={p.h1} intro={p.intro} trail={[{ name: c.ui.navTechnology, path: "/technology/" }]} />
      <article className="wrap narrow prose">
        <Prose sections={p.sections} locale={locale} />
      </article>
      {p.faq && <Faq items={p.faq} title={c.ui.faqTitle} locale={locale} />}
      <CtaBand locale={locale} />
    </Shell>
  );
}

export function DownloadPage({ locale }: { locale: Locale }) {
  const c = copy[locale];
  const p = c.download;
  return (
    <Shell locale={locale} path="/download/">
      <PageHero locale={locale} h1={p.h1} intro={p.intro} trail={[{ name: c.ui.navDownload, path: "/download/" }]} />
      <div className="wrap narrow">
        <DownloadButtons locale={locale} />
        <p className="muted small">
          {site.name} {site.version} ·{" "}
          <a href={releasesUrl} rel="noopener">
            {locale === "en" ? "All releases and checksums" : "Tutte le versioni e i checksum"}
          </a>
        </p>
        <ol className="steps">
          {p.steps.map((s, i) => (
            <li key={s.title}>
              <span className="step-n" aria-hidden="true">
                {i + 1}
              </span>
              <div>
                <h2 className="h3">{s.title}</h2>
                <p>
                  <Inline text={s.text} locale={locale} />
                </p>
              </div>
            </li>
          ))}
        </ol>
        <section className="note">
          <h2 className="h3">{p.gatekeeperTitle}</h2>
          <Paragraphs items={p.gatekeeperText} locale={locale} />
        </section>
        <div className="two-col">
          <section>
            <h2 className="h3">{p.requirementsTitle}</h2>
            <ul className="checklist">
              {p.requirements.map((r) => (
                <li key={r}>
                  <Icon name="check" size={16} />
                  <span>
                    <Inline text={r} locale={locale} />
                  </span>
                </li>
              ))}
            </ul>
          </section>
          <section>
            <h2 className="h3">{p.sourceTitle}</h2>
            <Paragraphs items={p.sourceText} locale={locale} />
            <pre className="code">
              <code>{`git clone ${site.repo}.git\ncd foglio\nscripts/build.sh\nopen build/Foglio.app`}</code>
            </pre>
          </section>
        </div>
      </div>
      <Faq items={p.faq} title={c.ui.faqTitle} locale={locale} />
      <JsonLd
        data={{
          "@context": "https://schema.org",
          "@type": "SoftwareApplication",
          "@id": `${site.url}/#app`,
          name: site.name,
          operatingSystem: `macOS ${site.minMacOS} or later`,
          applicationCategory: "BusinessApplication",
          softwareVersion: site.version,
          downloadUrl,
          fileSize: `${facts.dmgMB}MB`,
          isAccessibleForFree: true,
          offers: { "@type": "Offer", price: "0", priceCurrency: locale === "en" ? "USD" : "EUR" },
        }}
      />
    </Shell>
  );
}

type Kind = "alternatives" | "guides";
const lists: Record<Kind, Record<Locale, Article[]>> = { alternatives, guides };

export function ArticleIndexPage({ locale, kind }: { locale: Locale; kind: Kind }) {
  const c = copy[locale];
  const p = kind === "alternatives" ? c.alternativesIndex : c.guidesIndex;
  const label = kind === "alternatives" ? c.ui.navAlternatives : c.ui.navGuides;
  return (
    <Shell locale={locale} path={`/${kind}/`}>
      <PageHero locale={locale} h1={p.h1} intro={p.intro} trail={[{ name: label, path: `/${kind}/` }]} />
      <div className="wrap">
        <div className="cards cards-2">
          {lists[kind][locale].map((a) => (
            <Link key={a.slug} className="card card-link" href={href(locale, `/${kind}/${a.slug}/`)}>
              <h2 className="h3">{a.cardTitle}</h2>
              <p>{a.cardText}</p>
              <span className="text-link">
                {c.ui.readMore} <Icon name="arrow" size={16} />
              </span>
            </Link>
          ))}
        </div>
      </div>
      <CtaBand locale={locale} />
    </Shell>
  );
}

export function findArticle(kind: Kind, locale: Locale, slug: string): Article | undefined {
  return lists[kind][locale].find((a) => a.slug === slug);
}

export function articleSlugs(kind: Kind): { slug: string }[] {
  return lists[kind].en.map((a) => ({ slug: a.slug }));
}

export function ArticlePage({ locale, kind, slug }: { locale: Locale; kind: Kind; slug: string }) {
  const a = findArticle(kind, locale, slug);
  if (!a) notFound();
  const c = copy[locale];
  const label = kind === "alternatives" ? c.ui.navAlternatives : c.ui.navGuides;
  const path = `/${kind}/${a.slug}/`;
  const related = lists[kind][locale].filter((x) => x.slug !== a.slug);
  return (
    <Shell locale={locale} path={path}>
      <article>
        <header className="page-hero">
          <div className="wrap narrow">
            <Breadcrumbs
              locale={locale}
              trail={[
                { name: label, path: `/${kind}/` },
                { name: a.cardTitle, path },
              ]}
            />
            <h1>{a.h1}</h1>
            <Paragraphs items={a.intro} locale={locale} className="lead" />
            <p className="muted small">
              {c.ui.updated} <time dateTime={a.updated}>{formatDate(locale, a.updated)}</time>
            </p>
          </div>
        </header>
        {kind === "alternatives" && (
          <div className="wrap narrow">
            <Screenshot locale={locale} alt={plain(a.h1)} />
          </div>
        )}
        <div className="wrap narrow prose">
          <Prose sections={a.sections} locale={locale} />
        </div>
      </article>
      {a.faq && <Faq items={a.faq} title={c.ui.faqTitle} locale={locale} />}
      {related.length > 0 && (
        <section className="section" aria-labelledby="related">
          <div className="wrap">
            <h2 id="related">{label}</h2>
            <div className="cards cards-3">
              {related.map((r) => (
                <Link key={r.slug} className="card card-link" href={href(locale, `/${kind}/${r.slug}/`)}>
                  <h3>{r.cardTitle}</h3>
                  <p>{r.cardText}</p>
                </Link>
              ))}
            </div>
          </div>
        </section>
      )}
      <CtaBand locale={locale} />
      <JsonLd
        data={{
          "@context": "https://schema.org",
          "@type": kind === "guides" ? "TechArticle" : "Article",
          headline: plain(a.h1),
          description: a.meta.description,
          inLanguage: locale,
          dateModified: a.updated,
          datePublished: a.updated,
          mainEntityOfPage: absolute(locale, path),
          author: { "@type": "Organization", name: `${site.name} contributors`, url: site.repo },
          publisher: { "@type": "Organization", name: site.name, logo: { "@type": "ImageObject", url: `${site.url}/icon-256.png` } },
          image: `${site.url}/og-${locale}.png`,
        }}
      />
    </Shell>
  );
}

function CtaBand({ locale }: { locale: Locale }) {
  const h = copy[locale].home;
  return (
    <section className="section final-cta">
      <div className="wrap narrow center">
        <h2>{h.ctaTitle}</h2>
        <p className="lead">
          <Inline text={h.ctaText} locale={locale} />
        </p>
        <DownloadButtons locale={locale} center />
      </div>
    </section>
  );
}
