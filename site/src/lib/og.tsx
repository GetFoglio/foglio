import { readFileSync } from "node:fs";
import { join } from "node:path";
import { ImageResponse } from "next/og";
import { facts } from "@/content/facts";
import type { Locale } from "@/content/types";

const text: Record<Locale, { title: string; line: string }> = {
  en: {
    title: "The free, native spreadsheet for Mac",
    line: `Opens Excel files · ${facts.dmgMB} MB · launches in ${facts.launchSeconds} s · open source`,
  },
  it: {
    title: "Il foglio di calcolo gratuito e nativo per Mac",
    line: `Apre i file Excel · ${String(facts.dmgMB).replace(".", ",")} MB · si avvia in ${String(facts.launchSeconds).replace(".", ",")} s · open source`,
  },
};

/** 1200×630 social preview image, rendered once at build time. */
export function ogImage(locale: Locale) {
  const icon = readFileSync(join(process.cwd(), "public", "icon-256.png")).toString("base64");
  const t = text[locale];
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: "72px 88px",
          background: "linear-gradient(135deg, #f3fbf6 0%, #ffffff 55%, #e2f5ea 100%)",
          color: "#0d1f16",
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 28 }}>
          <img src={`data:image/png;base64,${icon}`} width={132} height={132} alt="" />
          <div style={{ fontSize: 88, fontWeight: 700, letterSpacing: -2 }}>Foglio</div>
        </div>
        <div style={{ fontSize: 58, fontWeight: 700, marginTop: 40, lineHeight: 1.1, letterSpacing: -1, maxWidth: 1000 }}>
          {t.title}
        </div>
        <div style={{ fontSize: 30, marginTop: 28, color: "#1b7a4a" }}>{t.line}</div>
      </div>
    ),
    { width: 1200, height: 630 },
  );
}
