import type { MetadataRoute } from "next";
import { alternatives, guides } from "@/content";
import { site } from "@/content/facts";
import { absolute } from "@/lib/i18n";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const pages: { path: string; priority: number; updated: string }[] = [
    { path: "/", priority: 1, updated: site.released },
    { path: "/download/", priority: 0.9, updated: site.released },
    { path: "/compare/", priority: 0.9, updated: site.released },
    { path: "/technology/", priority: 0.7, updated: site.released },
    { path: "/alternatives/", priority: 0.7, updated: site.released },
    { path: "/guides/", priority: 0.6, updated: site.released },
    ...alternatives.en.map((a) => ({ path: `/alternatives/${a.slug}/`, priority: 0.8, updated: a.updated })),
    ...guides.en.map((a) => ({ path: `/guides/${a.slug}/`, priority: 0.7, updated: a.updated })),
  ];
  return pages.flatMap((p) =>
    (["en", "it"] as const).map((locale) => ({
      url: absolute(locale, p.path),
      lastModified: p.updated,
      changeFrequency: "monthly" as const,
      priority: locale === "en" ? p.priority : Math.round(p.priority * 90) / 100,
      alternates: { languages: { en: absolute("en", p.path), it: absolute("it", p.path), "x-default": absolute("en", p.path) } },
    })),
  );
}
