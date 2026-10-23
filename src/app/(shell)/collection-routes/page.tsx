"use client";

// Task B — /collection-routes: route planning, truck assignments and pickup
// progress. Replaces the "coming online next" placeholder card.
//
// - Table of RT-1..RT-6 with truck / crew / sectors / stops / progress bar /
//   status chip (On schedule · Delayed family).
// - Planning panel: the selected route's ordered stop list (real RPT ids,
//   hydrated from the store) with **Assign** (cycles the crew assignment
//   client-side) and **Optimise order** (reorders the dummy stops by sector →
//   sub-sector → eta, no backend).
import { CheckCircle2, Route as RouteIcon, Wand2 } from "lucide-react";
import * as React from "react";

import {
  ASSIGNABLE_CREWS,
  ROUTES,
  ROUTE_TOTALS,
  type CollectionRoute,
} from "@/lib/data/routes";
import { formatClock } from "@/lib/mock-delay";
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
import { useToast } from "@/components/ui/use-toast";
import { cn } from "@/components/ui/utils";
import { PriorityDot } from "@/components/reports/PriorityDot";
import { StatusBadge } from "@/components/reports/StatusBadge";
import { mockDelay } from "@/lib/mock-delay";

function progressPct(route: CollectionRoute): number {
  if (route.stops.length === 0) return 0;
  return Math.round((route.done / route.stops.length) * 100);
}

/** On schedule → green chip (In Progress palette); Delayed → amber. */
function RouteStatusChip({ status }: { status: CollectionRoute["status"] }) {
  return (
    <Badge
      aria-label={`Route status: ${status}`}
      className={cn(
        "rounded-full px-2.5 py-0.5 text-xs font-semibold",
        status === "On schedule"
          ? "bg-[var(--chip-green-bg)] text-[var(--chip-green-text)]"
          : "bg-[var(--chip-amber-bg)] text-[var(--chip-amber-text)]"
      )}
    >
      {status}
    </Badge>
  );
}

function ProgressBar({ value }: { value: number }) {
  return (
    <div className="flex items-center gap-2">
      <div
        role="progressbar"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={value}
        aria-label={`Pickup progress ${value}%`}
        className="progress-track"
      >
        <div className="progress-fill" style={{ width: `${value}%` }} />
      </div>
      <span className="w-9 shrink-0 text-right text-xs font-semibold tabular-nums text-ink-primary">
        {value}%
      </span>
    </div>
  );
}

export default function CollectionRoutesPage() {
  const store = useStore();
  const { toast } = useToast();
  const [loading, setLoading] = React.useState(true);
  const [selectedId, setSelectedId] = React.useState<string>(ROUTES[0].id);
  // Client-side plan mutations over the dummy data (no backend).
  const [plan, setPlan] = React.useState(() =>
    Object.fromEntries(ROUTES.map((r) => [r.id, { ...r, stops: [...r.stops] }]))
  );

  React.useEffect(() => {
    let alive = true;
    void mockDelay().then(() => {
      if (alive) setLoading(false);
    });
    return () => {
      alive = false;
    };
  }, []);

  const selected = plan[selectedId];

  const assignNext = (routeId: string) => {
    const route = plan[routeId];
    const idx = ASSIGNABLE_CREWS.findIndex((c) => c.crew === route.crew);
    const next = ASSIGNABLE_CREWS[(idx + 1) % ASSIGNABLE_CREWS.length];
    setPlan((prev) => ({
      ...prev,
      [routeId]: { ...prev[routeId], crew: next.crew, lead: next.lead, truck: next.truck },
    }));
    toast({
      title: "Route reassigned",
      description: `${routeId} → ${next.crew} (${next.lead}) on ${next.truck}.`,
      variant: "success",
    });
  };

  const optimiseOrder = (routeId: string) => {
    setPlan((prev) => {
      const route = prev[routeId];
      const sorted = [...route.stops].sort((a, b) => {
        const ra = store.getReport(a.reportId);
        const rb = store.getReport(b.reportId);
        const sector = (ra?.sector ?? 0) - (rb?.sector ?? 0);
        if (sector !== 0) return sector;
        const subsector = (ra?.subsector ?? 0) - (rb?.subsector ?? 0);
        if (subsector !== 0) return subsector;
        return a.eta.localeCompare(b.eta);
      });
      return { ...prev, [routeId]: { ...route, stops: sorted } };
    });
    toast({
      title: "Stops optimised",
      description: `${routeId} stop order resequenced by sector → sub-sector → ETA.`,
    });
  };

  return (
    <div className="space-y-6 pb-10">
      <div>
        <h2 className="text-xl font-bold text-ink-primary">
          Collection Routes
        </h2>
        <p className="text-sm text-ink-secondary">
          {ROUTE_TOTALS.routes} routes today · {ROUTE_TOTALS.trucks} trucks ·{" "}
          {ROUTE_TOTALS.stops} stops · {ROUTE_TOTALS.delayed} delayed · updated
          5 min ago
        </p>
      </div>

      {/* Route table — truck / crew / sectors / stops / progress / status */}
      <section aria-label="Today's routes" className="space-y-3">
        {loading ? (
          <Skeleton className="h-72 rounded-[12px]" />
        ) : (
          <div className="panel-scroll overflow-x-auto rounded-[12px] border border-[var(--border-plain)] bg-[var(--surface)]">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead scope="col">Route</TableHead>
                  <TableHead scope="col">Truck</TableHead>
                  <TableHead scope="col">Crew</TableHead>
                  <TableHead scope="col" className="hidden sm:table-cell">
                    Sectors
                  </TableHead>
                  <TableHead scope="col">Stops</TableHead>
                  <TableHead scope="col" className="hidden md:table-cell">
                    Progress
                  </TableHead>
                  <TableHead scope="col">Status</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {ROUTES.map((route) => {
                  const live = plan[route.id];
                  const pct = progressPct(live);
                  const isActive = route.id === selectedId;
                  return (
                    <TableRow
                      key={route.id}
                      tabIndex={0}
                      role="button"
                      aria-pressed={isActive}
                      aria-label={`Plan route ${route.id} — ${live.crew} on ${live.truck}`}
                      onClick={() => setSelectedId(route.id)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter" || e.key === " ") {
                          e.preventDefault();
                          setSelectedId(route.id);
                        }
                      }}
                      className={cn(
                        "cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--focus-ring)]",
                        isActive && "bg-[var(--sidebar)]"
                      )}
                    >
                      <TableCell>
                        <span className="flex items-center gap-1.5 font-mono text-sm font-semibold text-ink-primary">
                          <RouteIcon
                            className="h-4 w-4 text-[var(--green-text)]"
                            aria-hidden="true"
                          />
                          {route.id}
                        </span>
                        <span className="text-xs text-ink-secondary">
                          {live.stream}
                        </span>
                      </TableCell>
                      <TableCell className="font-mono text-xs">
                        {live.truck}
                      </TableCell>
                      <TableCell>
                        <p className="whitespace-nowrap font-medium">
                          {live.crew}
                        </p>
                        <p className="text-xs text-ink-secondary">
                          {live.lead}
                        </p>
                      </TableCell>
                      <TableCell className="hidden whitespace-nowrap sm:table-cell">
                        {route.sectors.map((w) => `Sector ${w}`).join(", ")}
                      </TableCell>
                      <TableCell className="tabular-nums">
                        {live.done}/{live.stops.length}
                      </TableCell>
                      <TableCell className="hidden min-w-[140px] md:table-cell">
                        <ProgressBar value={pct} />
                      </TableCell>
                      <TableCell>
                        <RouteStatusChip status={live.status} />
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
        )}
      </section>

      {/* Planning panel — ordered stops + Assign / Optimise order */}
      {selected ? (
        <section aria-label={`Route plan for ${selected.id}`} className="space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h3 className="text-sm font-semibold text-ink-primary">
              Route plan · {selected.id} — {selected.crew} on {selected.truck}
            </h3>
            <div className="flex items-center gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={() => assignNext(selected.id)}
                aria-label={`Assign next crew to ${selected.id}`}
              >
                Assign
              </Button>
              <Button
                size="sm"
                onClick={() => optimiseOrder(selected.id)}
                aria-label={`Optimise stop order for ${selected.id}`}
              >
                <Wand2 className="h-4 w-4" aria-hidden="true" />
                Optimise order
              </Button>
            </div>
          </div>

          {selected.delayNote ? (
            <p
              role="status"
              className="inline-flex items-center gap-2 rounded-[8px] border border-[var(--chip-amber-border)] bg-[var(--chip-amber-bg)] px-3 py-2 text-xs font-medium text-[var(--chip-amber-text)]"
            >
              {selected.delayNote}
            </p>
          ) : null}

          <Card className="rounded-[12px]">
            <CardContent className="p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-ink-secondary">
                Ordered stops · {selected.done} of {selected.stops.length}{" "}
                collected
              </p>
              <ol className="mt-3 space-y-2">
                {selected.stops.map((stop, i) => {
                  const report = store.getReport(stop.reportId);
                  const collected = i < selected.done;
                  return (
                    <li
                      key={`${selected.id}-${stop.reportId}-${i}`}
                      className={cn(
                        "flex items-center gap-3 rounded-[8px] border px-3 py-2",
                        collected
                          ? "border-[var(--chip-green-border)] bg-[var(--chip-green-bg)]"
                          : "border-[var(--border-plain)] bg-[var(--input-bg)]"
                      )}
                    >
                      <span
                        aria-hidden="true"
                        className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-[var(--border-plain)] bg-[var(--surface)] text-[11px] font-bold tabular-nums text-ink-secondary"
                      >
                        {i + 1}
                      </span>
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-mono text-sm font-semibold text-ink-primary">
                          {stop.reportId}
                        </p>
                        <p className="truncate text-xs text-ink-secondary">
                          {report
                            ? `${report.category} · Sector ${report.sector} · Sub-sector ${report.subsector}`
                            : "Report not in the current dataset"}
                          {report ? ` · ETA ${stop.eta}` : ""}
                        </p>
                      </div>
                      {report ? (
                        <div className="hidden shrink-0 items-center gap-2 sm:flex">
                          <PriorityDot priority={report.priority} />
                          <StatusBadge status={report.status} />
                        </div>
                      ) : null}
                      {collected ? (
                        <CheckCircle2
                          className="h-4 w-4 shrink-0 text-[var(--green-text)]"
                          aria-label="Collected"
                        />
                      ) : (
                        <span className="shrink-0 text-xs text-ink-secondary">
                          ETA {stop.eta}
                        </span>
                      )}
                    </li>
                  );
                })}
              </ol>
              <p className="mt-3 text-xs text-ink-secondary">
                Next arrival {formatClock(`2026-10-23T${selected.stops[Math.min(selected.done, selected.stops.length - 1)]?.eta ?? "06:00"}:00`)} ·
                Assign and Optimise order update this plan in the browser only
                (no backend).
              </p>
            </CardContent>
          </Card>
        </section>
      ) : null}
    </div>
  );
}
