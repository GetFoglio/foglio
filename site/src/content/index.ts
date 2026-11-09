import type { Locale, SiteCopy } from "./types";
import { copyEn } from "./copy.en";
import { copyIt } from "./copy.it";

export const copy: Record<Locale, SiteCopy> = { en: copyEn, it: copyIt };
export { alternatives } from "./alternatives";
export { guides } from "./guides";
export * from "./comparison";
export * from "./facts";
export * from "./types";
