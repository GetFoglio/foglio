import type { Metadata } from "next";
import { copy } from "@/content";
import { pageMetadata } from "@/lib/metadata";
import { ArticleIndexPage } from "@/views/Pages";

export const metadata: Metadata = pageMetadata("it", "/guides/", copy.it.meta.guides);

export default function Page() {
  return <ArticleIndexPage locale="it" kind="guides" />;
}
