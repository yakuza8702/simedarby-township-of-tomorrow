"use client";

// Task B — /sectors: sector boundaries, collection calendars and crew
// rosters. Replaces the "coming online next" placeholder card. All dummy
// data from lib/data/sectors.ts; open-report counts come from the shared
// store so the page never contradicts the reports queue.
import * as React from "react";

import {
  COLLECTION_CALENDAR,
  CREWS,
  SECTOR_TOTALS,
  SECTOR_CARDS,
  STREAM_DOT,
  WEEKLY_COLLECTION_SLOTS,
  WEEK_DAYS,
  type WasteStream,
} from "@/lib/data/sectors";
import { mockDelay } from "@/lib/mock-delay";
import { useStore } from "@/lib/store";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { cn } from "@/components/ui/utils";

// Deterministic thousands formatting (avoids server/client locale drift on
// the prerendered client component).
function fmt(n: number): string {
  return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function StreamChip({ stream }: { stream: WasteStream }) {
  return (
    <span className="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full border border-[var(--border-plain)] bg-[var(--surface)] px-2 py-0.5 text-[11px] font-medium text-ink-primary">
      <span
        aria-hidden="true"
        className={cn("stream-dot", STREAM_DOT[stream])}
      />
      {stream}
    </span>
  );
}

export default function SectorsPage() {
  const store = useStore();
  const [loading, setLoading] = React.useState(true);
  // Boundary highlight: the sector whose schematic boundary is emphasised.
  const [highlighted, setHighlighted] = React.useState<number | null>(null);

  React.useEffect(() => {
    let alive = true;
    void mockDelay().then(() => {
      if (alive) setLoading(false);
    });
    return () => {
      alive = false;
    };
  }, []);

  const openBySector = React.useMemo(() => {
    const map = new Map<number, number>();
    store.reports
      .filter((r) => r.status === "Open")
      .forEach((r) => map.set(r.sector, (map.get(r.sector) ?? 0) + 1));
    return map;
  }, [store.reports]);

  return (
    <div className="space-y-6 pb-10">
      <div>
        <h2 className="text-xl font-bold text-ink-primary">Sectors</h2>
        <p className="text-sm text-ink-secondary">
          {SECTOR_TOTALS.sectors} sectors · {SECTOR_TOTALS.subsectors}{" "}
          sub-sectors · {fmt(SECTOR_TOTALS.households)} households · updated 5
          min ago
        </p>
      </div>

      {/* (1) Sector cards — boundary highlight + area / households / residents */}
      <section aria-label="Sector boundaries" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="text-sm font-semibold text-ink-primary">
            Sector boundaries
          </h3>
          <p className="text-xs text-ink-secondary">
            Boundary highlight marks the sub-sectors carrying the heaviest report
            load this week.
          </p>
        </div>

        {loading ? (
          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} className="h-36 rounded-[12px]" />
            ))}
          </div>
        ) : (
          <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            {SECTOR_CARDS.map((w) => {
              const active = highlighted === w.sector;
              const open = openBySector.get(w.sector) ?? 0;
              return (
                <li key={w.sector}>
                  <Card
                    className={cn(
                      "h-full rounded-[12px] transition-colors",
                      active && "border-[var(--chip-green-border)]"
                    )}
                  >
                    <CardContent className="flex h-full flex-col p-4">
                      <div className="flex items-start justify-between gap-2">
                        <p className="text-sm font-bold text-ink-primary">
                          Sector {w.sector}
                        </p>
                        {open > 0 ? (
                          <Badge className="rounded-full bg-[var(--chip-amber-bg)] text-[var(--chip-amber-text)]">
                            {open} open
                          </Badge>
                        ) : null}
                      </div>

                      {/* Schematic boundary — fills/highlights with the toggle. */}
                      <div
                        aria-hidden="true"
                        className={cn(
                          "mt-3 h-14 rounded-[8px] border border-dashed p-2 transition-colors",
                          active
                            ? "border-[var(--chip-green-border)] bg-[var(--chip-green-bg)]"
                            : "border-[var(--border-plain)] bg-[var(--input-bg)]"
                        )}
                      >
                        <div className="flex h-full items-center justify-center gap-1.5">
                          {w.subsectors.map((p) => (
                            <span
                              key={p}
                              className={cn(
                                "flex h-7 min-w-7 items-center justify-center rounded-[6px] border px-1 text-[11px] font-semibold",
                                active && w.hotSubsectors.includes(p)
                                  ? "border-[var(--chip-green-border)] bg-[var(--chip-green-bg)] text-[var(--chip-green-text)]"
                                  : "border-[var(--border-plain)] bg-[var(--surface)] text-ink-secondary"
                              )}
                            >
                              {p}
                            </span>
                          ))}
                        </div>
                      </div>

                      <dl className="mt-3 grid grid-cols-2 gap-x-3 gap-y-1 text-xs">
                        <dt className="text-ink-secondary">Area</dt>
                        <dd className="text-right font-medium text-ink-primary">
                          {w.areaKm2} km²
                        </dd>
                        <dt className="text-ink-secondary">Households</dt>
                        <dd className="text-right font-medium text-ink-primary">
                          {fmt(w.households)}
                        </dd>
                        <dt className="text-ink-secondary">Residents</dt>
                        <dd className="text-right font-medium text-ink-primary">
                          {fmt(w.residents)}
                        </dd>
                        <dt className="text-ink-secondary">Sector lead</dt>
                        <dd className="truncate text-right font-medium text-ink-primary">
                          {w.lead}
                        </dd>
                      </dl>

                      <Button
                        variant={active ? "secondary" : "outline"}
                        size="sm"
                        className="mt-3 w-full"
                        aria-pressed={active}
                        onClick={() => setHighlighted(active ? null : w.sector)}
                      >
                        {active
                          ? "Clear boundary highlight"
                          : "Boundary highlight"}
                      </Button>
                    </CardContent>
                  </Card>
                </li>
              );
            })}
          </ul>
        )}
      </section>

      {/* (2) Collection calendar — weekly table per sector with stream chips */}
      <section aria-label="Weekly collection calendar" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="text-sm font-semibold text-ink-primary">
            Collection calendar · this week
          </h3>
          <p className="text-xs text-ink-secondary">
            {WEEKLY_COLLECTION_SLOTS} scheduled pickups · stream chips match the
            console palette (organic #388E3C, recycling #1E88E5)
          </p>
        </div>

        {loading ? (
          <Skeleton className="h-56 rounded-[12px]" />
        ) : (
          <div className="panel-scroll overflow-x-auto rounded-[12px] border border-[var(--border-plain)] bg-[var(--surface)]">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead scope="col" className="w-24">
                    Sector
                  </TableHead>
                  {WEEK_DAYS.map((day) => (
                    <TableHead key={day} scope="col">
                      {day}
                    </TableHead>
                  ))}
                </TableRow>
              </TableHeader>
              <TableBody>
                {SECTOR_CARDS.map((w) => {
                  const days = COLLECTION_CALENDAR[w.sector] ?? {};
                  return (
                    <TableRow key={w.sector}>
                      <TableCell className="whitespace-nowrap font-semibold">
                        Sector {w.sector}
                      </TableCell>
                      {WEEK_DAYS.map((day) => {
                        const streams = days[day];
                        return (
                          <TableCell key={day}>
                            {streams && streams.length > 0 ? (
                              <div className="flex flex-wrap gap-1">
                                {streams.map((s) => (
                                  <StreamChip key={s} stream={s} />
                                ))}
                              </div>
                            ) : (
                              <span className="text-xs italic text-ink-secondary">
                                —
                              </span>
                            )}
                          </TableCell>
                        );
                      })}
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
        )}
      </section>

      {/* (3) Crew rosters — crew / sector / shift / lead */}
      <section aria-label="Crew rosters" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="text-sm font-semibold text-ink-primary">
            Crew rosters
          </h3>
          <p className="text-xs text-ink-secondary">
            {CREWS.length} crews · {CREWS.reduce((n, c) => n + c.members, 0)}{" "}
            crew members on rotation
          </p>
        </div>

        {loading ? (
          <Skeleton className="h-64 rounded-[12px]" />
        ) : (
          <div className="panel-scroll overflow-x-auto rounded-[12px] border border-[var(--border-plain)] bg-[var(--surface)]">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead scope="col">Crew</TableHead>
                  <TableHead scope="col">Sector</TableHead>
                  <TableHead scope="col">Shift</TableHead>
                  <TableHead scope="col">Lead</TableHead>
                  <TableHead scope="col" className="hidden sm:table-cell">
                    Members
                  </TableHead>
                  <TableHead scope="col" className="hidden md:table-cell">
                    Streams
                  </TableHead>
                  <TableHead scope="col" className="hidden lg:table-cell">
                    Truck
                  </TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {CREWS.map((crew) => (
                  <TableRow key={crew.id}>
                    <TableCell>
                      <p className="font-semibold text-ink-primary">
                        {crew.name}
                      </p>
                      <p className="font-mono text-xs text-ink-secondary">
                        {crew.id}
                      </p>
                    </TableCell>
                    <TableCell>Sector {crew.sector}</TableCell>
                    <TableCell className="whitespace-nowrap">
                      {crew.shift}
                    </TableCell>
                    <TableCell className="whitespace-nowrap font-medium">
                      {crew.lead}
                    </TableCell>
                    <TableCell className="hidden sm:table-cell">
                      {crew.members}
                    </TableCell>
                    <TableCell className="hidden md:table-cell">
                      <div className="flex flex-wrap gap-1">
                        {crew.streams.map((s) => (
                          <StreamChip key={s} stream={s} />
                        ))}
                      </div>
                    </TableCell>
                    <TableCell className="hidden font-mono text-xs lg:table-cell">
                      {crew.truck}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </section>
    </div>
  );
}
