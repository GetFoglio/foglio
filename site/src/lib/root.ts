import type { Metadata, Viewport } from "next";
import { site } from "@/content/facts";
import type { Locale } from "@/content/types";

export function rootMetadata(locale: Locale): Metadata {
  return {
    metadataBase: new URL(site.url),
    applicationName: site.name,
    authors: [{ name: `${site.name} contributors`, url: site.repo }],
    creator: `${site.name} contributors`,
    category: "technology",
    formatDetection: { telephone: false, email: false, address: false },
    robots: { index: true, follow: true, googleBot: { index: true, follow: true, "max-image-preview": "large", "max-snippet": -1 } },
    other: { "content-language": locale },
  };
}

export const rootViewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
    { media: "(prefers-color-scheme: dark)", color: "#0e1512" },
  ],
  colorScheme: "light dark",
  width: "device-width",
  initialScale: 1,
};
