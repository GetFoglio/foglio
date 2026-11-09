import type { ReactNode } from "react";
import { rootMetadata, rootViewport } from "@/lib/root";
import "../../globals.css";

export const metadata = rootMetadata("it");
export const viewport = rootViewport;

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="it">
      <body>{children}</body>
    </html>
  );
}
