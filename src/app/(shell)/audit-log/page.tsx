"use client";

// P2-SPEC §1 — Audit log: filter bar + audit table with Before → After column.
import * as React from "react";

import { AuditFilters, type AuditFilterState } from "@/components/audit/AuditFilters";
import { AuditTable } from "@/components/audit/AuditTable";
import { Button } from "@/components/ui/button";
import { AUDIT_ACTIONS, AUDIT_ACTORS } from "@/lib/data/audit";
import { exportAuditCsv } from "@/lib/csv";
import { mockDelay } from "@/lib/mock-delay";
import { useStore } from "@/lib/store";

export default function AuditLogPage() {
  const store = useStore();
  const [filters, setFilters] = React.useState<AuditFilterState>({
    actor: "all",
    action: "all",
    from: "",
    to: "",
  });
  const [loading, setLoading] = React.useState(true);
  const [announcement, setAnnouncement] = React.useState("");

  // Simulated refetch whenever the filter state changes.
  React.useEffect(() => {
    let alive = true;
    setLoading(true);
    void mockDelay().then(() => {
      if (alive) setLoading(false);
    });
    return () => {
      alive = false;
    };
  }, [filters]);

  const filtered = React.useMemo(() => {
    return store.auditEntries.filter((entry) => {
      if (filters.actor !== "all" && entry.actor !== filters.actor)
        return false;
      if (filters.action !== "all" && entry.action !== filters.action)
        return false;
      const day = entry.time.slice(0, 10);
      if (filters.from && day < filters.from) return false;
      if (filters.to && day > filters.to) return false;
      return true;
    });
  }, [store.auditEntries, filters]);

  const hasFilters =
    filters.actor !== "all" ||
    filters.action !== "all" ||
    Boolean(filters.from) ||
    Boolean(filters.to);

  return (
    <div className="space-y-5 pb-10">
      <div>
        <h2 className="text-xl font-bold text-ink-primary">Audit log</h2>
        <p className="text-sm text-ink-secondary">
          Every change, who made it, and what changed · October 2026
        </p>
      </div>

      <AuditFilters
        actors={AUDIT_ACTORS}
        actions={AUDIT_ACTIONS}
        state={filters}
        onChange={setFilters}
        onExport={() => {
          exportAuditCsv(filtered, "audit-log.csv");
          setAnnouncement("Export complete");
          window.setTimeout(() => setAnnouncement(""), 2500);
        }}
      />

      <p className="sr-only" role="status" aria-live="polite">
        {announcement}
      </p>

      <p aria-live="polite" className="text-xs text-ink-secondary">
        {loading
          ? "Loading audit entries…"
          : `Showing ${filtered.length} of ${store.auditEntries.length} entries`}
      </p>

      {!loading && filtered.length === 0 ? (
        <div className="flex flex-col items-center justify-center gap-3 rounded-[12px] border border-dashed border-[var(--border-plain)] bg-[var(--input-bg)] px-6 py-16 text-center">
          <p className="text-sm font-medium text-ink-primary">
            No audit entries match these filters. Clear or widen your search.
          </p>
          <Button
            variant="ghost"
            size="sm"
            onClick={() =>
              setFilters({ actor: "all", action: "all", from: "", to: "" })
            }
          >
            Clear filters
          </Button>
        </div>
      ) : (
        <AuditTable entries={filtered} loading={loading} />
      )}
    </div>
  );
}
