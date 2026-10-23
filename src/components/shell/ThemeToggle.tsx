"use client";

// Task C — light/dark toggle for the console topbar.
// - Default is LIGHT; the choice persists in localStorage under
//   "township-theme" and is applied before paint by the inline boot script in
//   src/app/layout.tsx (no hydration flash).
// - The icon syncs from the DOM on mount (server always renders the Sun) so
//   React never hydrates a mismatched icon.
import * as React from "react";
import { Moon, Sun } from "lucide-react";

import { Button } from "@/components/ui/button";

export const THEME_STORAGE_KEY = "township-theme";

export function isDarkTheme(): boolean {
  if (typeof document === "undefined") return false;
  return document.documentElement.classList.contains("dark");
}

export function ThemeToggle() {
  const [dark, setDark] = React.useState(false);

  React.useEffect(() => {
    setDark(isDarkTheme());
  }, []);

  const toggle = () => {
    const next = !isDarkTheme();
    document.documentElement.classList.toggle("dark", next);
    try {
      window.localStorage.setItem(THEME_STORAGE_KEY, next ? "dark" : "light");
    } catch {
      /* storage disabled — theme still applies for this page view */
    }
    setDark(next);
  };

  return (
    <Button
      variant="ghost"
      size="icon"
      onClick={toggle}
      aria-pressed={dark}
      aria-label={dark ? "Switch to light mode" : "Switch to dark mode"}
      title={dark ? "Switch to light mode" : "Switch to dark mode"}
      className="h-9 w-9 shrink-0 rounded-full"
    >
      {dark ? (
        <Moon className="h-4 w-4" aria-hidden="true" />
      ) : (
        <Sun className="h-4 w-4" aria-hidden="true" />
      )}
    </Button>
  );
}
