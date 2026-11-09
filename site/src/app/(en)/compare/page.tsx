import type { Metadata } from "next";
import { copy } from "@/content";
import { pageMetadata } from "@/lib/metadata";
import { ComparePage } from "@/views/Pages";

export const metadata: Metadata = pageMetadata("en", "/compare/", copy.en.meta.compare);

export default function Page() {
  return <ComparePage locale="en" />;
}
