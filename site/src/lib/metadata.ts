import type { Metadata } from "next";
import type { Locale, Meta } from "@/content/types";
import { site } from "@/content/facts";
import { absolute, href, ogLocale, otherLocale } from "./i18n";

/** Page metadata with canonical URL, hreflang alternates and Open Graph / Twitter cards. */
export function pageMetadata(locale: Locale, path: string, meta: Meta, type: "website" | "article" = "website"): Metadata {
  const url = absolute(locale, path);
  return {
    title: meta.title,
    description: meta.description,
    alternates: {
      canonical: href(locale, path),
      languages: {
        en: href("en", path),
        it: href("it", path),
        "x-default": href("en", path),
      },
    },
    openGraph: {
      type,
      url,
      siteName: site.name,
      title: meta.ogTitle ?? meta.title,
      description: meta.description,
      locale: ogLocale[locale],
      alternateLocale: [ogLocale[otherLocale(locale)]],
      images: [{ url: `/og-${locale}.png`, width: 1200, height: 630, alt: meta.ogTitle ?? meta.title }],
    },
    twitter: {
      card: "summary_large_image",
      title: meta.ogTitle ?? meta.title,
      description: meta.description,
      images: [`/og-${locale}.png`],
    },
  };
}
