import type { Metadata } from "next";
import { copy } from "@/content";
import { pageMetadata } from "@/lib/metadata";
import { ArticleIndexPage } from "@/views/Pages";

export const metadata: Metadata = pageMetadata("it", "/alternatives/", copy.it.meta.alternatives);

export default function Page() {
  return <ArticleIndexPage locale="it" kind="alternatives" />;
}
