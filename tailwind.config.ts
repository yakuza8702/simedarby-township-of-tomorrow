import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: ["class"],
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    container: {
      center: true,
      padding: "1.5rem",
      screens: { "2xl": "1200px" },
    },
    extend: {
      fontFamily: {
        // Source-Sans-like system stack — no remote fonts (offline constraint).
        sans: [
          '"Source Sans Pro"',
          '"Source Sans 3"',
          "ui-sans-serif",
          "system-ui",
          "-apple-system",
          '"Segoe UI"',
          "Roboto",
          '"Helvetica Neue"',
          "Arial",
          '"Noto Sans"',
          "sans-serif",
        ],
      },
      colors: {
        // Task C — dark mode: every token below is backed by a CSS variable
        // defined in globals.css; light values equal the original hexes
        // exactly, the `.dark` block swaps them. Solid brand fills (destructive
        // red, warn amber, review blue, checkbox green) keep literal hexes —
        // they read correctly on both backgrounds.
        primary: { DEFAULT: "var(--green-solid)", ink: "#1C1B1F" },
        success: "var(--green-solid-hover)",
        warn: {
          DEFAULT: "#F9A825",
          ink: "var(--chip-amber-text)",
          tint: "var(--chip-amber-bg)",
        },
        error: { DEFAULT: "var(--error-strong)", soft: "var(--error-soft)" },
        review: { DEFAULT: "#1E88E5", tint: "var(--chip-blue-bg)" },
        surface: {
          DEFAULT: "var(--surface)",
          input: "var(--input-bg)",
          sidebar: "var(--sidebar)",
          active: "var(--active-tint)",
        },
        ink: {
          primary: "var(--ink-primary)",
          secondary: "var(--ink-secondary)",
          tertiary: "var(--ink-tertiary)",
        },
        divider: "var(--border-plain)",
        border: "var(--border-plain)",
        background: "var(--background)",
      },
      borderRadius: {
        lg: "var(--radius)",
        md: "calc(var(--radius) - 4px)",
        sm: "calc(var(--radius) - 6px)",
      },
      keyframes: {
        "accordion-down": {
          from: { height: "0" },
          to: { height: "var(--radix-accordion-content-height)" },
        },
        "accordion-up": {
          from: { height: "var(--radix-accordion-content-height)" },
          to: { height: "0" },
        },
      },
      animation: {
        "accordion-down": "accordion-down 0.2s ease-out",
        "accordion-up": "accordion-up 0.2s ease-out",
      },
    },
  },
  plugins: [require("tailwindcss-animate")],
};

export default config;
