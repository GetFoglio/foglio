import Link from "next/link";
import type { ReactNode } from "react";
import type { Locale } from "@/content/types";
import { href } from "@/lib/i18n";

// **bold**, `code`, [text](url)
const TOKEN = /(\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\]\([^)\s]+\))/g;

/** Renders the content model's tiny inline markup (see content/types.ts). */
export function Inline({ text, locale }: { text: string; locale: Locale }) {
  const parts = text.split(TOKEN);
  const out: ReactNode[] = parts.map((part, i) => {
    if (part.startsWith("**") && part.endsWith("**")) return <strong key={i}>{part.slice(2, -2)}</strong>;
    if (part.startsWith("`") && part.endsWith("`")) return <code key={i}>{part.slice(1, -1)}</code>;
    const link = /^\[([^\]]+)\]\(([^)\s]+)\)$/.exec(part);
    if (link) {
      const [, label, url] = link as unknown as [string, string, string];
      if (url.startsWith("/")) return <Link key={i} href={href(locale, url)}>{label}</Link>;
      return (
        <a key={i} href={url} rel="noopener" target="_blank">
          {label}
        </a>
      );
    }
    return part;
  });
  return <>{out}</>;
}

/** Strips the inline markup, for JSON-LD and meta tags. */
export function plain(text: string): string {
  return text
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\[([^\]]+)\]\([^)\s]+\)/g, "$1");
}
