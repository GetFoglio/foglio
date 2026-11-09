import type { Metadata } from "next";
import { copy } from "@/content";
import { pageMetadata } from "@/lib/metadata";
import { ArticleIndexPage } from "@/views/Pages";

export const metadata: Metadata = pageMetadata("en", "/guides/", copy.en.meta.guides);

export default function Page() {
  return <ArticleIndexPage locale="en" kind="guides" />;
}
