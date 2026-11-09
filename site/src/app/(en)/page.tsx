import type { Metadata } from "next";
import { copy } from "@/content";
import { pageMetadata } from "@/lib/metadata";
import { HomePage } from "@/views/Home";

export const metadata: Metadata = pageMetadata("en", "/", copy.en.meta.home);

export default function Page() {
  return <HomePage locale="en" />;
}
