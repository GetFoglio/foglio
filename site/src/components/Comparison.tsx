import { comparisonApps, comparisonRows } from "@/content";
import type { AppId, ComparisonCell, ComparisonRow, Locale } from "@/content/types";
import { copy } from "@/content";
import { Icon } from "./Icon";

const order: AppId[] = ["foglio", "excel", "numbers", "libreoffice", "sheets"];

function cellText(c: ComparisonCell, locale: Locale) {
  return typeof c.text === "string" ? c.text : c.text[locale];
}

function Cell({ c, locale }: { c: ComparisonCell; locale: Locale }) {
  const t = copy[locale].ui;
  const icon = c.tone === "good" ? "check" : c.tone === "bad" ? "cross" : c.tone === "partial" ? "dash" : null;
  const label = c.tone === "good" ? t.yes : c.tone === "bad" ? t.no : c.tone === "partial" ? t.partial : "";
  return (
    <span className={`cell tone-${c.tone}`}>
      {icon && (
        <span className="tone-icon" role="img" aria-label={label}>
          <Icon name={icon} size={14} />
        </span>
      )}
      <span>{cellText(c, locale)}</span>
    </span>
  );
}

/**
 * Full comparison table, grouped. Plain HTML table (indexable, accessible); the first column
 * sticks while the table scrolls horizontally on small screens.
 */
export function ComparisonTable({
  locale,
  rows = comparisonRows,
  apps = order,
  caption,
}: {
  locale: Locale;
  rows?: ComparisonRow[];
  apps?: AppId[];
  caption: string;
}) {
  const groups: { name: string; rows: ComparisonRow[] }[] = [];
  for (const r of rows) {
    const g = r.group[locale];
    const last = groups[groups.length - 1];
    if (last && last.name === g) last.rows.push(r);
    else groups.push({ name: g, rows: [r] });
  }
  return (
    <div className="table-scroll" tabIndex={0} role="region" aria-label={caption}>
      <table className="compare">
        <caption className="sr-only">{caption}</caption>
        <thead>
          <tr>
            <td />
            {apps.map((a) => (
              <th key={a} scope="col" className={a === "foglio" ? "is-foglio" : undefined}>
                <span className="app-name">{comparisonApps[a].name}</span>
                <span className="app-maker">{comparisonApps[a].maker}</span>
              </th>
            ))}
          </tr>
        </thead>
        {groups.map((g) => (
          <tbody key={g.name}>
            <tr className="group-row">
              <th scope="colgroup" colSpan={apps.length + 1}>
                {g.name}
              </th>
            </tr>
            {g.rows.map((r) => (
              <tr key={r.label.en}>
                <th scope="row">{r.label[locale]}</th>
                {apps.map((a) => (
                  <td key={a} className={a === "foglio" ? "is-foglio" : undefined}>
                    <Cell c={r.cells[a]} locale={locale} />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        ))}
      </table>
    </div>
  );
}

/** Horizontal bars; values on a log-free linear scale, labelled with the exact number. */
export function Bars({
  items,
  unit,
  title,
  note,
}: {
  items: { label: string; value: number; display: string; highlight?: boolean }[];
  unit: string;
  title: string;
  note?: string;
}) {
  const max = Math.max(...items.map((i) => i.value));
  return (
    <figure className="bars">
      <figcaption>
        <span className="bars-title">{title}</span>
        <span className="muted small">{unit}</span>
      </figcaption>
      <ul>
        {items.map((i) => (
          <li key={i.label} className={i.highlight ? "hl" : undefined}>
            <span className="bar-label">{i.label}</span>
            <span className="bar-track">
              <span className="bar-fill" style={{ width: `${Math.max(0.6, (i.value / max) * 100)}%` }} />
            </span>
            <span className="bar-value">{i.display}</span>
          </li>
        ))}
      </ul>
      {note && <p className="muted small">{note}</p>}
    </figure>
  );
}
