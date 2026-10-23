"use client";

// P2-SPEC §6 — audit table: Time / Actor / Action / Entity / Before → After,
// rows expand to a full diff detail.
import { ChevronDown, ChevronRight } from "lucide-react";
import * as React from "react";

import type { AuditEntry, ReportStatus } from "@/lib/types";
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
import { StatusBadge } from "@/components/reports/StatusBadge";

function entityLabel(entry: AuditEntry): string {
  return entry.entity.kind === "Role"
    ? `Role ${entry.entity.userId}`
    : `${entry.entity.kind} ${entry.entity.id}`;
}

// V9 — status-bearing strings (e.g. the "In Progress → Resolved" pair) reuse
// the shared StatusBadge instead of plain text.
const REPORT_STATUSES: ReadonlySet<string> = new Set<ReportStatus>([
  "Open",
  "In review",
  "In Progress",
  "Resolved",
]);

function asStatus(value: string): ReportStatus | null {
  return REPORT_STATUSES.has(value) ? (value as ReportStatus) : null;
}

interface AuditTableProps {
  entries: AuditEntry[];
  loading: boolean;
}

export function AuditTable({ entries, loading }: AuditTableProps) {
  const [expandedId, setExpandedId] = React.useState<string | null>(null);

  return (
    <div className="overflow-hidden rounded-[12px] border border-[var(--border-plain)] bg-[var(--surface)]">
      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <TableHead scope="col" className="w-8">
              <span className="sr-only">Expand</span>
            </TableHead>
            <TableHead scope="col">Time</TableHead>
            <TableHead scope="col">Actor</TableHead>
            <TableHead scope="col">Action</TableHead>
            <TableHead scope="col" className="hidden md:table-cell">
              Entity
            </TableHead>
            <TableHead scope="col">Before → After</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {loading
            ? Array.from({ length: 6 }).map((_, i) => (
                <TableRow key={`skeleton-${i}`} className="hover:bg-transparent">
                  <TableCell>
                    <Skeleton className="h-4 w-4" />
                  </TableCell>
                  <TableCell>
                    <Skeleton className="h-4 w-28" />
                  </TableCell>
                  <TableCell>
                    <Skeleton className="h-4 w-20" />
                  </TableCell>
                  <TableCell>
                    <Skeleton className="h-4 w-24" />
                  </TableCell>
                  <TableCell className="hidden md:table-cell">
                    <Skeleton className="h-4 w-28" />
                  </TableCell>
                  <TableCell>
                    <Skeleton className="h-4 w-40" />
                  </TableCell>
                </TableRow>
              ))
            : entries.map((entry) => {
                const expanded = expandedId === entry.id;
                return (
                  <React.Fragment key={entry.id}>
                    <TableRow
                      tabIndex={0}
                      role="button"
                      aria-expanded={expanded}
                      aria-label={`Audit ${entry.id}: ${entry.action} by ${entry.actor}`}
                      className={cn(
                        "cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--focus-ring)]",
                        expanded && "bg-[var(--row-hover)]"
                      )}
                      onClick={() =>
                        setExpandedId(expanded ? null : entry.id)
                      }
                      onKeyDown={(e) => {
                        if (e.key === "Enter" || e.key === " ") {
                          e.preventDefault();
                          setExpandedId(expanded ? null : entry.id);
                        }
                      }}
                    >
                      <TableCell>
                        {expanded ? (
                          <ChevronDown
                            className="h-4 w-4 text-ink-secondary"
                            aria-hidden="true"
                          />
                        ) : (
                          <ChevronRight
                            className="h-4 w-4 text-ink-secondary"
                            aria-hidden="true"
                          />
                        )}
                      </TableCell>
                      <TableCell className="whitespace-nowrap font-mono text-xs text-ink-secondary">
                        {entry.time.slice(0, 10)} {entry.time.slice(11, 16)}
                      </TableCell>
                      <TableCell className="whitespace-nowrap font-medium">
                        {entry.actor}
                      </TableCell>
                      <TableCell className="whitespace-nowrap">
                        {entry.action}
                      </TableCell>
                      <TableCell className="hidden whitespace-nowrap font-mono text-xs text-ink-secondary md:table-cell">
                        {entityLabel(entry)}
                      </TableCell>
                      <TableCell>
                        <span className="text-ink-secondary line-through decoration-[var(--error-text)]">
                          {asStatus(entry.before) ? (
                            <StatusBadge status={asStatus(entry.before)!} />
                          ) : (
                            entry.before
                          )}
                        </span>
                        <span className="mx-1.5 text-ink-secondary" aria-hidden="true">
                          →
                        </span>
                        <span className="font-medium text-ink-primary">
                          {asStatus(entry.after) ? (
                            <StatusBadge status={asStatus(entry.after)!} />
                          ) : (
                            entry.after
                          )}
                        </span>
                      </TableCell>
                    </TableRow>
                    {expanded ? (
                      <TableRow className="hover:bg-transparent">
                        <TableCell colSpan={6} className="bg-[var(--input-bg)] p-4">
                          <div className="grid gap-3 text-sm sm:grid-cols-2">
                            <div className="rounded-[8px] border border-[var(--border-plain)] bg-[var(--surface)] p-3">
                              <p className="text-xs font-semibold uppercase tracking-wide text-ink-secondary">
                                Before
                              </p>
                              <p className="mt-1 text-ink-primary">
                                {entry.before}
                              </p>
                            </div>
                            <div className="rounded-[8px] border border-[var(--border-green)] bg-[var(--sidebar)] p-3">
                              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--green-text)]">
                                After
                              </p>
                              <p className="mt-1 text-ink-primary">
                                {entry.after}
                              </p>
                            </div>
                            <dl className="sm:col-span-2 grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-ink-secondary">
                              <dt className="font-semibold">Entry</dt>
                              <dd className="font-mono">{entry.id}</dd>
                              <dt className="font-semibold">Entity</dt>
                              <dd className="font-mono">{entityLabel(entry)}</dd>
                              <dt className="font-semibold">Recorded</dt>
                              <dd>{entry.time.replace("T", " ")}</dd>
                            </dl>
                          </div>
                        </TableCell>
                      </TableRow>
                    ) : null}
                  </React.Fragment>
                );
              })}
        </TableBody>
      </Table>
    </div>
  );
}
