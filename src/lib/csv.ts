import type { AuditEntry, Report } from "./types";

/** Escape one CSV cell (RFC-4180-ish quoting). */
function cell(value: string | number): string {
  return `"${String(value).replace(/"/g, '""')}"`;
}

function download(csv: string, filename: string): void {
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

/** P2-SPEC §6 — export the currently filtered report rows as CSV (client-side Blob). */
export function exportReportsCsv(rows: Report[], filename = "reports.csv"): void {
  const header = [
    "ID",
    "Category",
    "Priority",
    "Sector",
    "Sub-sector",
    "Status",
    "Reported",
    "Assignee",
  ];
  const body = rows.map((r) => [
    r.id,
    r.category,
    r.priority,
    r.sector,
    r.subsector,
    r.status,
    r.reportedAt,
    r.assignee ?? "Unassigned",
  ]);
  const csv = [header, ...body]
    .map((row) => row.map(cell).join(","))
    .join("\n");
  download(csv, filename);
}

export function exportAuditCsv(
  rows: AuditEntry[],
  filename = "audit-log.csv"
): void {
  const header = ["Time", "Actor", "Action", "Entity", "Before", "After"];
  const body = rows.map((e) => [
    e.time,
    e.actor,
    e.action,
    `${e.entity.kind} ${"id" in e.entity ? e.entity.id : e.entity.userId}`,
    e.before,
    e.after,
  ]);
  const csv = [header, ...body]
    .map((row) => row.map(cell).join(","))
    .join("\n");
  download(csv, filename);
}
