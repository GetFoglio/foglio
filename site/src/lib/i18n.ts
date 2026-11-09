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

/** Base path for raw asset URLs (next/link adds it automatically, <img> does not). */
export const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";
export const asset = (p: string) => `${basePath}${p}`;

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
