import type { Metadata } from "next";
import { copy } from "@/content";
import { pageMetadata } from "@/lib/metadata";
import { DownloadPage } from "@/views/Pages";

export const metadata: Metadata = pageMetadata("it", "/download/", copy.it.meta.download);

export default function Page() {
  return <DownloadPage locale="it" />;
}
