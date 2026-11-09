import type { ReactNode } from "react";
import { rootMetadata, rootViewport } from "@/lib/root";
import "../globals.css";

export const metadata = rootMetadata("en");
export const viewport = rootViewport;

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
