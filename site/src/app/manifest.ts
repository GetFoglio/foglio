import type { MetadataRoute } from "next";
import { site } from "@/content/facts";

export const dynamic = "force-static";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: `${site.name} — spreadsheet for Mac`,
    short_name: site.name,
    start_url: "/",
    display: "browser",
    background_color: "#ffffff",
    theme_color: "#1e9e5e",
    icons: [
      { src: "/icon-256.png", sizes: "256x256", type: "image/png" },
      { src: "/icon.png", sizes: "512x512", type: "image/png" },
    ],
  };
}
