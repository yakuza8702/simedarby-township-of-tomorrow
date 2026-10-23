import type { Metadata, Viewport } from "next";

import "./globals.css";

export const metadata: Metadata = {
  title: "Township of Tomorrow · Admin Console",
  description:
    "Council operations console — waste, reports, and collection in one place",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
};

// Task C — no-hydration-flash theme boot: read the persisted choice from
// localStorage (default LIGHT — no system-follow) and flip the `dark` class
// on <html> before first paint. Inline (no extra request), runs before React
// hydrates, and <html suppressHydrationWarning> keeps the server's classless
// render from fighting the client-side class (React skips the mismatch warn).
const THEME_BOOT_SCRIPT = `(function(){try{if(localStorage.getItem("township-theme")==="dark"){document.documentElement.classList.add("dark");}}catch(e){}})();`;

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_BOOT_SCRIPT }} />
      </head>
      <body className="min-h-screen bg-[var(--background)] font-sans text-ink-primary">
        {children}
      </body>
    </html>
  );
}
