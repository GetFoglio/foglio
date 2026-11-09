import type { Feature } from "@/content/types";

type Name = Feature["icon"] | "check" | "cross" | "dash" | "download" | "github" | "arrow" | "menu";

const paths: Record<Name, string> = {
  bolt: "M13 2 4 14h7l-1 8 9-12h-7l1-8z",
  feather: "M20.2 3.8a6 6 0 0 0-8.5 0L5 10.5V19h8.5l6.7-6.7a6 6 0 0 0 0-8.5zM16 8 2 22M17.5 15H9",
  gift: "M20 12v10H4V12M2 7h20v5H2zM12 22V7M12 7H7.5a2.5 2.5 0 1 1 0-5C11 2 12 7 12 7zM12 7h4.5a2.5 2.5 0 1 0 0-5C13 2 12 7 12 7z",
  file: "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8zM14 2v6h6M8 13h8M8 17h8M8 9h2",
  function: "M9 20c2 0 2.5-2 3-5l1.5-7c.5-3 1-4 3-4M7 10h9M15 15l5 5M20 15l-5 5",
  chart: "M3 3v18h18M7 16v-4M12 16V8M17 16v-7",
  globe: "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM2 12h20M12 2a15 15 0 0 1 0 20M12 2a15 15 0 0 0 0 20",
  lock: "M5 11h14v11H5zM8 11V7a4 4 0 0 1 8 0v4",
  apple: "M4 5h16v11H4zM2 20h20",
  code: "m16 18 6-6-6-6M8 6l-6 6 6 6",
  image: "M3 3h18v18H3zM8.5 10a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3zM21 15l-5-5L5 21",
  filter: "M22 3H2l8 9.5V19l4 2v-8.5z",
  check: "M20 6 9 17l-5-5",
  cross: "M18 6 6 18M6 6l12 12",
  dash: "M5 12h14",
  download: "M12 3v12M7 10l5 5 5-5M5 21h14",
  github:
    "M9 19c-5 1.5-5-2.5-7-3m14 6v-3.9a3.4 3.4 0 0 0-.9-2.6c3.1-.3 6.4-1.5 6.4-7A5.4 5.4 0 0 0 20 4.8 5 5 0 0 0 19.9 1S18.7.7 16 2.5a13.4 13.4 0 0 0-7 0C6.3.7 5.1 1 5.1 1A5 5 0 0 0 5 4.8a5.4 5.4 0 0 0-1.5 3.7c0 5.4 3.3 6.6 6.4 7A3.4 3.4 0 0 0 9 18.1V22",
  arrow: "M5 12h14M13 6l6 6-6 6",
  menu: "M3 6h18M3 12h18M3 18h18",
};

export function Icon({ name, size = 20, className }: { name: Name; size?: number; className?: string }) {
  return (
    <svg
      className={className}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d={paths[name]} />
    </svg>
  );
}
