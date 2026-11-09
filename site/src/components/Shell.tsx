import Link from "next/link";
import type { ReactNode } from "react";
import { copy } from "@/content";
import { downloadUrl, site } from "@/content/facts";
import type { Locale } from "@/content/types";
import { asset, href, otherLocale } from "@/lib/i18n";
import { Icon } from "./Icon";

/** Header + main + footer around every page. `path` is the locale-less path of the page. */
export function Shell({ locale, path, children }: { locale: Locale; path: string; children: ReactNode }) {
  const t = copy[locale].ui;
  const other = otherLocale(locale);
  const nav = [
    { label: t.navCompare, to: "/compare/" },
    { label: t.navTechnology, to: "/technology/" },
    { label: t.navAlternatives, to: "/alternatives/" },
    { label: t.navGuides, to: "/guides/" },
  ];
  const navLinks = nav.map((n) => (
    <Link key={n.to} href={href(locale, n.to)} aria-current={path.startsWith(n.to) ? "page" : undefined}>
      {n.label}
    </Link>
  ));
  return (
    <>
      <a className="skip" href="#main">
        {t.skipToContent}
      </a>
      <header className="site-header">
        <div className="wrap header-row">
          <Link href={href(locale, "/")} className="brand" aria-label={`${site.name} — home`}>
            <img src={asset("/icon-256.png")} width={32} height={32} alt="" />
            <span>{site.name}</span>
          </Link>
          <nav className="nav-desktop" aria-label="Main">
            {navLinks}
          </nav>
          <div className="header-actions">
            <Link className="lang" href={href(other, path)} hrefLang={other} lang={other}>
              {t.languageName}
            </Link>
            <a className="icon-link" href={site.repo} aria-label={t.navGitHub} rel="noopener">
              <Icon name="github" size={20} />
            </a>
            <a className="btn btn-small" href={downloadUrl}>
              <Icon name="download" size={16} />
              {t.navDownload}
            </a>
            <details className="nav-mobile">
              <summary aria-label="Menu">
                <Icon name="menu" size={22} />
              </summary>
              <nav aria-label="Mobile">
                {navLinks}
                <Link href={href(locale, "/download/")}>{t.navDownload}</Link>
                <a href={site.repo} rel="noopener">
                  {t.navGitHub}
                </a>
              </nav>
            </details>
          </div>
        </div>
      </header>
      <main id="main">{children}</main>
      <Footer locale={locale} />
    </>
  );
}

function Footer({ locale }: { locale: Locale }) {
  const t = copy[locale].ui;
  const cols: { title: string; links: { label: string; to: string; ext?: boolean }[] }[] = [
    {
      title: site.name,
      links: [
        { label: t.navDownload, to: "/download/" },
        { label: t.navCompare, to: "/compare/" },
        { label: t.navTechnology, to: "/technology/" },
      ],
    },
    {
      title: t.navAlternatives,
      links: [
        { label: "Excel", to: "/alternatives/excel-for-mac/" },
        { label: "Numbers", to: "/alternatives/numbers/" },
        { label: "LibreOffice", to: "/alternatives/libreoffice/" },
        { label: "Google Sheets", to: "/alternatives/google-sheets/" },
      ],
    },
    {
      title: "Open source",
      links: [
        { label: "GitHub", to: site.repo, ext: true },
        { label: "Releases", to: `${site.repo}/releases`, ext: true },
        { label: "Issues", to: `${site.repo}/issues`, ext: true },
        { label: t.navGuides, to: "/guides/" },
      ],
    },
  ];
  return (
    <footer className="site-footer">
      <div className="wrap footer-grid">
        <div>
          <div className="brand">
            <img src={asset("/icon-256.png")} width={28} height={28} alt="" />
            <span>{site.name}</span>
          </div>
          <p className="muted">{t.footerTagline}</p>
          <p className="muted small">{t.footerLicense}</p>
        </div>
        {cols.map((c) => (
          <div key={c.title}>
            <h2 className="footer-title">{c.title}</h2>
            <ul>
              {c.links.map((l) => (
                <li key={l.to}>
                  {l.ext ? (
                    <a href={l.to} rel="noopener">
                      {l.label}
                    </a>
                  ) : (
                    <Link href={href(locale, l.to)}>{l.label}</Link>
                  )}
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
      <div className="wrap">
        <p className="muted small trademark">{t.footerTrademark}</p>
      </div>
    </footer>
  );
}
