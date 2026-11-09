import type { FAQ, Locale } from "@/content/types";
import { Inline, plain } from "./Inline";
import { JsonLd } from "./JsonLd";

/** Accordion of questions (no JavaScript: <details>) plus FAQPage structured data. */
export function Faq({ items, title, locale, id = "faq" }: { items: FAQ[]; title: string; locale: Locale; id?: string }) {
  if (!items.length) return null;
  return (
    <section className="section" aria-labelledby={id}>
      <div className="wrap narrow">
        <h2 id={id}>{title}</h2>
        <div className="faq">
          {items.map((f) => (
            <details key={f.q}>
              <summary>{f.q}</summary>
              <p>
                <Inline text={f.a} locale={locale} />
              </p>
            </details>
          ))}
        </div>
      </div>
      <JsonLd
        data={{
          "@context": "https://schema.org",
          "@type": "FAQPage",
          mainEntity: items.map((f) => ({
            "@type": "Question",
            name: plain(f.q),
            acceptedAnswer: { "@type": "Answer", text: plain(f.a) },
          })),
        }}
      />
    </section>
  );
}
