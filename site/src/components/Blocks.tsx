import Link from "next/link";
import type { Locale, Section } from "@/content/types";
import { downloadUrl, site } from "@/content/facts";
import { copy } from "@/content";
import { absolute, asset, href } from "@/lib/i18n";
import { Icon } from "./Icon";
import { Inline } from "./Inline";
import { JsonLd } from "./JsonLd";

/** Long-form sections: h2, paragraphs, bullets, h3 sub-sections. */
export function Prose({ sections, locale }: { sections: Section[]; locale: Locale }) {
  return (
    <>
      {sections.map((s) => (
        <section key={s.heading} className="prose-section">
          <h2>{s.heading}</h2>
          {s.body.map((p, i) => (
            <p key={i}>
              <Inline text={p} locale={locale} />
            </p>
          ))}
          {s.bullets && (
            <ul>
              {s.bullets.map((b, i) => (
                <li key={i}>
                  <Inline text={b} locale={locale} />
                </li>
              ))}
            </ul>
          )}
          {s.sub?.map((sub) => (
            <div key={sub.heading}>
              <h3>{sub.heading}</h3>
              {sub.body.map((p, i) => (
                <p key={i}>
                  <Inline text={p} locale={locale} />
                </p>
              ))}
              {sub.bullets && (
                <ul>
                  {sub.bullets.map((b, i) => (
                    <li key={i}>
                      <Inline text={b} locale={locale} />
                    </li>
                  ))}
                </ul>
              )}
            </div>
          ))}
        </section>
      ))}
    </>
  );
}

export function Paragraphs({ items, locale, className }: { items: string[]; locale: Locale; className?: string }) {
  return (
    <>
      {items.map((p, i) => (
        <p key={i} className={className}>
          <Inline text={p} locale={locale} />
        </p>
      ))}
    </>
  );
}

/** Visible breadcrumb trail + BreadcrumbList structured data. */
export function Breadcrumbs({ locale, trail }: { locale: Locale; trail: { name: string; path: string }[] }) {
  const all = [{ name: site.name, path: "/" }, ...trail];
  return (
    <nav aria-label="Breadcrumb" className="crumbs">
      <ol>
        {all.map((c, i) => (
          <li key={c.path}>
            {i < all.length - 1 ? <Link href={href(locale, c.path)}>{c.name}</Link> : <span aria-current="page">{c.name}</span>}
          </li>
        ))}
      </ol>
      <JsonLd
        data={{
          "@context": "https://schema.org",
          "@type": "BreadcrumbList",
          itemListElement: all.map((c, i) => ({
            "@type": "ListItem",
            position: i + 1,
            name: c.name,
            item: absolute(locale, c.path),
          })),
        }}
      />
    </nav>
  );
}

export function DownloadButtons({ locale, center }: { locale: Locale; center?: boolean }) {
  const t = copy[locale].ui;
  return (
    <div className={center ? "cta-row center" : "cta-row"}>
      <a className="btn btn-primary" href={downloadUrl}>
        <Icon name="download" size={18} />
        {t.download}
      </a>
      <a className="btn btn-ghost" href={site.repo} rel="noopener">
        <Icon name="github" size={18} />
        {t.viewSource}
      </a>
      <p className="cta-sub">{t.downloadSub}</p>
    </div>
  );
}

/**
 * Real screenshot of the app, light or dark following the visitor's system setting.
 * AVIF (≈20 KB) with WebP fallback, two widths, explicit size so nothing shifts while loading.
 */
export function Screenshot({ locale, alt, priority }: { locale: Locale; alt: string; priority?: boolean }) {
  const set = (theme: string, ext: string) =>
    [720, 1213].map((w) => `${asset(`/screenshots/${locale}-${theme}-${w}.${ext}`)} ${w}w`).join(", ");
  const sizes = "(max-width: 1112px) calc(100vw - 32px), 1080px";
  return (
    <figure className="shot">
      <picture>
        <source type="image/avif" srcSet={set("dark", "avif")} sizes={sizes} media="(prefers-color-scheme: dark)" />
        <source type="image/webp" srcSet={set("dark", "webp")} sizes={sizes} media="(prefers-color-scheme: dark)" />
        <source type="image/avif" srcSet={set("light", "avif")} sizes={sizes} />
        <img
          src={asset(`/screenshots/${locale}-light-1213.webp`)}
          srcSet={set("light", "webp")}
          sizes={sizes}
          width={1213}
          height={813}
          alt={alt}
          fetchPriority={priority ? "high" : "auto"}
          loading={priority ? "eager" : "lazy"}
          decoding="async"
        />
      </picture>
    </figure>
  );
}

export function PageHero({
  locale,
  h1,
  intro,
  trail,
}: {
  locale: Locale;
  h1: string;
  intro: string[];
  trail: { name: string; path: string }[];
}) {
  return (
    <header className="page-hero">
      <div className="wrap narrow">
        <Breadcrumbs locale={locale} trail={trail} />
        <h1>{h1}</h1>
        <Paragraphs items={intro} locale={locale} className="lead" />
      </div>
    </header>
  );
}

/** "We are not trying to be Excel": the project's goal, shown on the home and the comparison page. */
export function Positioning({ locale, headingLevel = 2 }: { locale: Locale; headingLevel?: 2 | 3 }) {
  const p = copy[locale].positioning;
  const H = headingLevel === 2 ? "h2" : "h3";
  return (
    <div className="positioning">
      <div className="positioning-text">
        <H id="goal">{p.title}</H>
        <Paragraphs items={p.text} locale={locale} />
      </div>
      <ul className="positioning-points">
        {p.points.map((pt) => (
          <li key={pt.title}>
            <strong>{pt.title}</strong>
            <span>
              <Inline text={pt.text} locale={locale} />
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}
