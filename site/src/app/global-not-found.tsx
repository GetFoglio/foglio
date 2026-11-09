import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Page not found | Foglio",
  robots: { index: false },
};

const base = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

export default function GlobalNotFound() {
  return (
    <html lang="en">
      <body>
        <main className="notfound">
          <img src={`${base}/icon-256.png`} width={96} height={96} alt="" />
          <h1>404</h1>
          <p>This page does not exist. · Questa pagina non esiste.</p>
          <p className="cta-row center">
            <a className="btn btn-primary" href={`${base}/`}>
              Foglio — Home
            </a>
            <a className="btn btn-ghost" href={`${base}/it/`}>
              Foglio — Italiano
            </a>
          </p>
        </main>
      </body>
    </html>
  );
}
