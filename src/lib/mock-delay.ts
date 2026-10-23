// P2-SPEC §5 — mock 250–400ms delay to exercise skeleton states.
export const MOCK_DELAY_MIN = 250;
export const MOCK_DELAY_JITTER = 150;

export function mockDelay(): Promise<void> {
  return new Promise((resolve) =>
    setTimeout(resolve, Math.random() * MOCK_DELAY_JITTER + MOCK_DELAY_MIN)
  );
}

/**
 * Frozen "now" for deterministic SLA / relative-time maths across the dummy
 * October 2026 dataset (INFERRED). The drawer countdown ticks on top of this.
 */
export const FROZEN_NOW_ISO = "2026-10-23T18:06:00";

export function frozenNow(): Date {
  return new Date(FROZEN_NOW_ISO);
}

// Wall-clock instant the module first loaded (client side) — used to advance
// the frozen clock for mutation stamps without ever reading the real date.
const APP_LOADED_AT = Date.now();

/**
 * Frozen "now" advanced by the real time elapsed since the app loaded
 * (frozenNow + elapsedSinceLoad). Mutations stamp this so new audit rows /
 * timeline events always sort after the seeded October 2026 rows in any
 * browser timezone — never `new Date()` / `toISOString()`.
 */
export function frozenNowTick(): Date {
  return new Date(frozenNow().getTime() + (Date.now() - APP_LOADED_AT));
}

/**
 * Naive-local "YYYY-MM-DDTHH:mm:ss" formatter — the exact string style the
 * seed data stores. Pure local getters only; never round-trips through
 * toISOString() (which would shift times in non-UTC browsers).
 */
export function formatNaiveLocal(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return (
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
    `T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
  );
}

export function formatDuration(ms: number): string {
  const abs = Math.abs(ms);
  const totalMinutes = Math.floor(abs / 60_000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return `${hours}h ${String(minutes).padStart(2, "0")}m`;
}

export function formatClock(iso: string): string {
  const d = new Date(iso);
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  return `${hh}:${mm}`;
}

export function formatDateTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}
