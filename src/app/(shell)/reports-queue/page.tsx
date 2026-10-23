"use client";

// P2-SPEC §6 — reports queue: filters (URL-synced), KPI row, queue tabs,
// table ⇄ map toggle, pagination and the detail drawer.
import { useRouter, useSearchParams } from "next/navigation";
import * as React from "react";

import {
  CATEGORIES,
  OPEN_KPI_COUNT,
  SUBSECTORS,
  PRIORITIES,
  RESOLVED_LIFETIME_COUNT,
  STATUSES,
  IN_REVIEW_KPI_COUNT,
  AVG_FIRST_RESPONSE_HOURS,
} from "@/lib/data/reports";
import { exportReportsCsv } from "@/lib/csv";
import { mockDelay } from "@/lib/mock-delay";
import { useStore } from "@/lib/store";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { cn } from "@/components/ui/utils";
import { DetailDrawer } from "@/components/reports/detail-drawer";
import { Filters, EMPTY_FILTERS, type ReportFilters } from "@/components/reports/Filters";
import { KpiRow } from "@/components/reports/KpiRow";
import { MapView } from "@/components/reports/MapView";
import { Pagination } from "@/components/reports/Pagination";
import { ReportsTable } from "@/components/reports/ReportsTable";

const PAGE_SIZE = 6;

type TabKey = "all" | "mine" | "unassigned";
type ViewKey = "table" | "map";

function splitParam(value: string | null): string[] {
  return value ? value.split(",").filter(Boolean) : [];
}

function ReportsQueue() {
  const store = useStore();
  const router = useRouter();
  const searchParams = useSearchParams();

  const [search, setSearch] = React.useState("");
  const [filters, setFilters] = React.useState<ReportFilters>(EMPTY_FILTERS);
  const [tab, setTab] = React.useState<TabKey>("all");
  const [view, setView] = React.useState<ViewKey>("table");
  const [page, setPage] = React.useState(1);
  const [loading, setLoading] = React.useState(true);
  const [selectedId, setSelectedId] = React.useState<string | null>(null);
  const [announcement, setAnnouncement] = React.useState("");
  const hydratedRef = React.useRef(false);

  // Hydrate state from the URL once (P2-SPEC §6: filters live in the query).
  React.useEffect(() => {
    if (hydratedRef.current) return;
    hydratedRef.current = true;
    const statuses = splitParam(searchParams.get("status"));
    setFilters({
      categories: splitParam(searchParams.get("cat")),
      priorities: splitParam(searchParams.get("pri")),
      statuses: statuses.length > 0 ? statuses : ["Open"],
      subsectors: splitParam(searchParams.get("subsector")),
    });
    const t = searchParams.get("tab");
    if (t === "mine" || t === "unassigned") setTab(t);
    const v = searchParams.get("view");
    if (v === "map") setView("map");
    const q = searchParams.get("q");
    if (q) setSearch(q);
  }, [searchParams]);

  // Mirror state into the URL query string.
  React.useEffect(() => {
    const params = new URLSearchParams();
    if (filters.categories.length)
      params.set("cat", filters.categories.join(","));
    if (filters.priorities.length)
      params.set("pri", filters.priorities.join(","));
    const isDefaultStatus =
      filters.statuses.length === 1 && filters.statuses[0] === "Open";
    if (filters.statuses.length && !isDefaultStatus)
      params.set("status", filters.statuses.join(","));
    if (filters.subsectors.length)
      params.set("subsector", filters.subsectors.join(","));
    if (tab !== "all") params.set("tab", tab);
    if (view !== "table") params.set("view", view);
    if (search.trim()) params.set("q", search.trim());
    const qs = params.toString();
    router.replace(qs ? `/reports-queue?${qs}` : "/reports-queue", {
      scroll: false,
    });
  }, [filters, tab, view, search, router]);

  // Simulated refetch (250–400ms) whenever filter/search input changes.
  React.useEffect(() => {
    let alive = true;
    setLoading(true);
    void mockDelay().then(() => {
      if (alive) setLoading(false);
    });
    return () => {
      alive = false;
    };
  }, [filters, search]);

  React.useEffect(() => {
    setPage(1);
  }, [filters, search, tab]);

  const openCount = store.reports.filter((r) => r.status === "Open").length;

  const filteredRows = React.useMemo(() => {
    const q = search.trim().toLowerCase();
    return store.reports.filter((r) => {
      if (
        filters.categories.length > 0 &&
        !filters.categories.includes(r.category)
      )
        return false;
      if (
        filters.priorities.length > 0 &&
        !filters.priorities.includes(r.priority)
      )
        return false;
      if (filters.statuses.length > 0 && !filters.statuses.includes(r.status))
        return false;
      if (
        filters.subsectors.length > 0 &&
        !filters.subsectors.includes(String(r.subsector))
      )
        return false;
      if (tab === "mine" && r.assignee !== store.currentUser.fullName)
        return false;
      if (tab === "unassigned" && r.assignee !== null) return false;
      if (q) {
        const haystack = [
          r.id,
          r.category,
          r.assignee ?? "unassigned",
          r.citizenName,
          r.description,
        ]
          .join(" ")
          .toLowerCase();
        if (!haystack.includes(q)) return false;
      }
      return true;
    });
  }, [store.reports, store.currentUser.fullName, filters, search, tab]);

  // Task A — the map mirrors the Android counterpart: it always plots the
  // Open + In review work (subject to the category/priority/sub-sector/search
  // filters above), regardless of which status the table is filtered to.
  const mapRows = React.useMemo(
    () => filteredRows.filter((r) => r.status === "Open" || r.status === "In review"),
    [filteredRows]
  );

  const pageCount = Math.max(1, Math.ceil(filteredRows.length / PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const pageRows = filteredRows.slice(
    (safePage - 1) * PAGE_SIZE,
    safePage * PAGE_SIZE
  );

  const handleExport = () => {
    exportReportsCsv(filteredRows, "reports-queue.csv");
    setAnnouncement("Export complete");
    window.setTimeout(() => setAnnouncement(""), 2500);
  };

  const clearFilters = () => {
    setFilters(EMPTY_FILTERS);
    setSearch("");
  };

  return (
    <div className="space-y-5 pb-10">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-xl font-bold text-ink-primary">
            Reports queue
          </h2>
          <p className="text-sm text-ink-secondary">
            {openCount === 24
              ? "24 resident reports · updated 5 min ago"
              : `${openCount} resident reports · updated 5 min ago`}
          </p>
        </div>
        <div
          role="group"
          aria-label="View mode"
          className="flex items-center gap-1 rounded-[8px] border border-[var(--border-plain)] bg-[var(--input-bg)] p-1"
        >
          <Button
            variant="ghost"
            size="sm"
            aria-pressed={view === "table"}
            onClick={() => setView("table")}
            className={cn(
              "rounded-[8px] text-xs",
              view === "table" && "bg-[var(--active-tint)] text-[var(--green-text)] shadow-sm"
            )}
          >
            Table
          </Button>
          <Button
            variant="ghost"
            size="sm"
            aria-pressed={view === "map"}
            onClick={() => setView("map")}
            className={cn(
              "rounded-[8px] text-xs",
              view === "map" && "bg-[var(--active-tint)] text-[var(--green-text)] shadow-sm"
            )}
          >
            Map
          </Button>
        </div>
      </div>

      <KpiRow
        kpis={[
          {
            label: "Open reports",
            // K7: KPI numbers are static seeded aggregates (spec §6) — drawer
            // actions mutate the table only, never the KPI cards.
            value: String(OPEN_KPI_COUNT),
            footnote: "Needs review or dispatch",
          },
          {
            label: "In review",
            value: String(IN_REVIEW_KPI_COUNT),
            footnote: "Crew assigned",
          },
          {
            label: "Resolved this week",
            value: String(RESOLVED_LIFETIME_COUNT),
            footnote: "Lifetime weekly aggregate",
          },
          {
            label: "Avg first response",
            value: AVG_FIRST_RESPONSE_HOURS,
            footnote: "Report → first assignment",
          },
        ]}
      />

      <Filters
        search={search}
        onSearchChange={setSearch}
        filters={filters}
        onFiltersChange={setFilters}
        categoryOptions={[...CATEGORIES]}
        priorityOptions={[...PRIORITIES]}
        statusOptions={[...STATUSES]}
        subsectorOptions={SUBSECTORS.map((p) => String(p))}
        onExport={handleExport}
      />

      <p className="sr-only" role="status" aria-live="polite">
        {announcement}
      </p>

      <Tabs
        value={tab}
        onValueChange={(v) => setTab(v as TabKey)}
        aria-label="Queue filter"
      >
        <TabsList>
          <TabsTrigger value="all">
            All open{" "}
            <span className="ml-1 inline-flex items-center rounded-full bg-[var(--chip-amber-bg)] px-1.5 py-0.5 text-[11px] font-semibold text-[var(--chip-amber-text)]">
              {openCount}
            </span>
          </TabsTrigger>
          <TabsTrigger value="mine">
            My tickets{" "}
            <span className="ml-1 inline-flex items-center rounded-full bg-[var(--chip-amber-bg)] px-1.5 py-0.5 text-[11px] font-semibold text-[var(--chip-amber-text)]">
              7
            </span>
          </TabsTrigger>
          <TabsTrigger value="unassigned">
            Unassigned{" "}
            <span className="ml-1 inline-flex items-center rounded-full bg-[var(--chip-amber-bg)] px-1.5 py-0.5 text-[11px] font-semibold text-[var(--chip-amber-text)]">
              23
            </span>
          </TabsTrigger>
        </TabsList>
      </Tabs>

      {view === "table" ? (
        <div className="space-y-3">
          {!loading && filteredRows.length === 0 ? (
            <div className="flex flex-col items-center justify-center gap-3 rounded-[12px] border border-dashed border-[var(--border-plain)] bg-[var(--input-bg)] px-6 py-16 text-center">
              <p className="text-sm font-medium text-ink-primary">
                No reports match these filters. Clear or widen your search.
              </p>
              <Button variant="ghost" size="sm" onClick={clearFilters}>
                Clear filters
              </Button>
            </div>
          ) : (
            <>
              <ReportsTable
                rows={pageRows}
                loading={loading}
                selectedId={selectedId}
                onSelect={setSelectedId}
              />
              <Pagination
                page={safePage}
                pageSize={PAGE_SIZE}
                total={filteredRows.length}
                onPageChange={setPage}
              />
            </>
          )}
        </div>
      ) : (
        <MapView reports={mapRows} onOpenDrawer={setSelectedId} />
      )}

      <DetailDrawer
        reportId={selectedId}
        onClose={() => setSelectedId(null)}
      />
    </div>
  );
}

export default function ReportsQueuePage() {
  return (
    <React.Suspense
      fallback={
        <div className="space-y-5 pb-10">
          <div className="space-y-2">
            <Skeleton className="h-7 w-44" />
            <Skeleton className="h-4 w-64" />
          </div>
          <div className="grid grid-cols-2 gap-4 xl:grid-cols-4">
            {Array.from({ length: 4 }).map((_, i) => (
              <Skeleton key={i} className="h-24 rounded-[12px]" />
            ))}
          </div>
          <Skeleton className="h-9 w-full" />
          <Skeleton className="h-10 w-72 rounded-[8px]" />
          <Skeleton className="h-[380px] rounded-[12px]" />
        </div>
      }
    >
      <ReportsQueue />
    </React.Suspense>
  );
}
