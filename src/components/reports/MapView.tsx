"use client";

// P2-SPEC §6 / Task A — map view on real OpenStreetMap tiles (leaflet).
//
// Replaces the inline-SVG/offline schematic map. Sector chips (verbatim design
// labels) filter which pins render; pins are one per Open + In review report
// coloured with the design priority palette; neighbours merge into cluster
// circles with count badges (simple client-side clustering, no lib); the
// subline is computed from the live dummy data; the mini card offers the
// selected (default: most recent) report with "Open drawer" — the same
// 380px detail drawer used by the table.
//
// Leaflet itself is imported through next/dynamic ssr:false (MapCanvas) so
// the production build stays static-safe; tiles need internet at RUNTIME
// only and degrade to a grey grid surface when offline.
import dynamic from "next/dynamic";
import { MapPinned } from "lucide-react";
import * as React from "react";

import { formatClock } from "@/lib/mock-delay";
import type { Report } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { cn } from "@/components/ui/utils";
import { PriorityDot } from "./PriorityDot";
import { StatusBadge } from "./StatusBadge";
import { mostRecent, type MapCanvasStats } from "./map-utils";

// ssr:false — leaflet touches window/document; the grey placeholder below
// keeps the layout stable until the map hydrates client-side.
const MapCanvas = dynamic(() => import("./MapCanvas"), {
  ssr: false,
  loading: () => (
    <div className="map-tile-bg map-grid absolute inset-0 flex items-center justify-center">
      <p className="rounded-[8px] border border-[var(--border-plain)] bg-[var(--surface-90)] px-3 py-2 text-xs text-ink-secondary">
        Loading OpenStreetMap…
      </p>
    </div>
  ),
});

/** Verbatim design chips (Appendix B). Sector 5 reports show under "All sectors". */
const SECTOR_CHIPS = ["All sectors", "Sector 1", "Sector 3", "Sector 7"] as const;

interface MapViewProps {
  /** Open + In review rows (the Android counterpart maps both statuses). */
  reports: Report[];
  /** Opens the shared 380px report drawer. */
  onOpenDrawer: (id: string) => void;
}

export function MapView({ reports, onOpenDrawer }: MapViewProps) {
  const [sector, setSector] = React.useState<string>("All sectors");
  const [stats, setStats] = React.useState<MapCanvasStats>({
    pins: 0,
    clusters: 0,
  });
  const [selectedId, setSelectedId] = React.useState<string | null>(null);

  const sectorFiltered = React.useMemo(() => {
    if (sector === "All sectors") return reports;
    const n = Number(sector.replace("Sector ", ""));
    return reports.filter((r) => r.sector === (n as Report["sector"]));
  }, [reports, sector]);

  // Default selection = most recently reported pin (mini card anchor).
  const fallback = React.useMemo(() => mostRecent(sectorFiltered), [sectorFiltered]);
  const selected =
    sectorFiltered.find((r) => r.id === selectedId) ?? fallback ?? null;

  // "updated HH:MM" — freshest report timestamp in the current sector filter.
  const updated = fallback ? formatClock(fallback.reportedAt) : "—";

  const handleSelect = React.useCallback(
    (id: string, source: "pin" | "cluster") => {
      setSelectedId(id);
      // Task A: clicking a pin opens the same drawer as the table; cluster
      // clicks only re-select (the card's "Open drawer" completes the trip).
      if (source === "pin") onOpenDrawer(id);
    },
    [onOpenDrawer]
  );

  return (
    <section aria-label="Map view" className="space-y-3">
      <div
        role="group"
        aria-label="Sector filter"
        className="flex flex-wrap items-center gap-2"
      >
        {SECTOR_CHIPS.map((chip) => {
          const active = sector === chip;
          return (
            <button
              key={chip}
              type="button"
              aria-pressed={active}
              onClick={() => {
                setSector(chip);
                setSelectedId(null);
              }}
              className={cn(
                "rounded-full border px-3 py-1 text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--focus-ring)]",
                active
                  ? "border-[var(--chip-green-border)] bg-[var(--chip-green-bg)] text-[var(--chip-green-text)]"
                  : "border-[var(--border-plain)] bg-[var(--surface)] text-ink-secondary hover:bg-[var(--sidebar)]"
              )}
            >
              {chip}
            </button>
          );
        })}
        {/* Live subline — computed from the dummy dataset, not hardcoded. */}
        <span className="ml-auto flex items-center gap-1.5 text-xs text-ink-secondary">
          <MapPinned className="h-4 w-4" aria-hidden="true" />
          {stats.pins + stats.clusters} pin
          {stats.pins + stats.clusters === 1 ? "" : "s"} · {stats.clusters}{" "}
          cluster{stats.clusters === 1 ? "" : "s"} · updated {updated}
        </span>
      </div>

      <div className="space-y-3 rounded-[12px] border border-[var(--border-plain)] bg-[var(--surface)] p-3">
        {/* Task A a11y: the map surface is an ARIA map region; pins are also
            exposed as a labelled button list below for keyboard/AT users. */}
        <div
          role="map"
          aria-label={`OpenStreetMap of ${sectorFiltered.length} reports in ${sector}`}
          className="relative h-[460px] overflow-hidden rounded-[12px] border border-[var(--border-plain)]"
        >
          <MapCanvas
            reports={sectorFiltered}
            selectedId={selected?.id ?? null}
            onSelect={handleSelect}
            onStats={setStats}
            fitKey={sector}
          />

          {sectorFiltered.length === 0 ? (
            <div className="pointer-events-none absolute inset-0 z-[500] flex items-center justify-center">
              <p className="rounded-[12px] border border-[var(--border-plain)] bg-[var(--surface-90)] px-4 py-3 text-sm text-ink-secondary">
                No pins for {sector.toLowerCase()} with the current filters.
              </p>
            </div>
          ) : null}

          {/* Mini card — design copy pattern "RPT-2401 · Illegal dumping · 08:12". */}
          {selected ? (
            <div
              role="group"
              aria-label={`Selected report ${selected.id}`}
              className="absolute bottom-3 left-3 z-[600] w-[292px] rounded-[12px] border border-[var(--border-plain)] bg-[var(--surface)] p-3 shadow-lg"
            >
              <div className="flex items-start justify-between gap-2">
                <p className="text-sm font-semibold text-ink-primary">
                  {selected.id} · {selected.category} ·{" "}
                  {formatClock(selected.reportedAt)}
                </p>
                <PriorityDot priority={selected.priority} className="mt-0.5" />
              </div>
              <p className="mt-1 text-xs text-ink-secondary">
                Sector {selected.sector} · Sub-sector {selected.subsector} ·{" "}
                {selected.assignee ?? "Unassigned"}
              </p>
              <div className="mt-2 flex items-center justify-between gap-2">
                <StatusBadge status={selected.status} />
                <Button
                  size="sm"
                  onClick={() => onOpenDrawer(selected.id)}
                  aria-label={`Open drawer for ${selected.id}`}
                >
                  Open drawer
                </Button>
              </div>
            </div>
          ) : null}

          <div className="pointer-events-none absolute right-3 top-3 z-[600] rounded-[8px] border border-[var(--border-plain)] bg-[var(--surface-90)] px-3 py-2 text-[11px] text-ink-secondary">
            Map data © OpenStreetMap contributors · tiles load at runtime
            (offline: grey grid, pins stay interactive)
          </div>
        </div>

        {/* Visually-hidden pin list — every visible pin is a labelled button
            that opens the same drawer (keyboard/AT parity with the map). */}
        <ul className="sr-only" aria-label="Map pins">
          {sectorFiltered.map((r) => (
            <li key={r.id}>
              <button
                type="button"
                onClick={() => onOpenDrawer(r.id)}
                aria-label={`${r.id} — ${r.category}, Sector ${r.sector}, Sub-sector ${r.subsector}, ${r.priority} priority, ${r.status}`}
              >
                {r.id} · {r.category} · Sector {r.sector}
              </button>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
