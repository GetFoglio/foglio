import type { Locale } from "@/content/types";
import { site } from "@/content/facts";

/** Locale-aware internal path: "/compare/" → "/it/compare/" for Italian. */
export function href(locale: Locale, path: string): string {
  const p = path.startsWith("/") ? path : `/${path}`;
  if (locale === "en") return p;
  return p === "/" ? "/it/" : `/it${p}`;
}

/** Absolute canonical URL on the production domain. */
export function absolute(locale: Locale, path: string): string {
  return `${site.url}${href(locale, path)}`;
}

export const otherLocale = (l: Locale): Locale => (l === "en" ? "it" : "en");

export const htmlLang: Record<Locale, string> = { en: "en", it: "it" };
export const ogLocale: Record<Locale, string> = { en: "en_US", it: "it_IT" };

/** URL of a file in public/ (kept as a function so a base path can be added in one place). */
export const asset = (p: string) => p;

export function formatDate(locale: Locale, iso: string): string {
  return new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  }).format(new Date(`${iso}T00:00:00Z`));
}

export function formatNumber(locale: Locale, n: number): string {
  return new Intl.NumberFormat(locale === "en" ? "en-US" : "it-IT").format(n);
}
