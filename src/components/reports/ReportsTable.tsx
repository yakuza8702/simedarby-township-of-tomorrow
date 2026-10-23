"use client";

import { formatClock, frozenNow } from "@/lib/mock-delay";
import { slaLabel } from "@/lib/sla";
import type { Report } from "@/lib/types";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
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
import { PriorityDot } from "./PriorityDot";
import { StatusBadge } from "./StatusBadge";

interface ReportsTableProps {
  rows: Report[];
  loading: boolean;
  selectedId: string | null;
  onSelect: (id: string) => void;
}

function initials(name: string): string {
  return name
    .replace(".", "")
    .split(" ")
    .map((p) => p[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();
}

export function ReportsTable({
  rows,
  loading,
  selectedId,
  onSelect,
}: ReportsTableProps) {
  const now = frozenNow().getTime();

  const activate = (event: React.KeyboardEvent | React.MouseEvent, id: string) => {
    if ("key" in event) {
      if (event.key !== "Enter" && event.key !== " ") return;
      event.preventDefault();
    }
    onSelect(id);
  };

  return (
    <div className="overflow-hidden rounded-[12px] border border-[var(--border-plain)] bg-[var(--surface)]">
      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <TableHead scope="col">Report</TableHead>
            <TableHead scope="col" className="hidden md:table-cell">
              Sector
            </TableHead>
            <TableHead scope="col" className="hidden lg:table-cell">
              Sub-sector
            </TableHead>
            <TableHead scope="col">Status</TableHead>
            <TableHead scope="col" className="hidden sm:table-cell">
              Reported
            </TableHead>
            <TableHead scope="col">Assignee</TableHead>
            <TableHead scope="col" className="hidden xl:table-cell">
              SLA
            </TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {loading
            ? Array.from({ length: 6 }).map((_, i) => (
                <TableRow key={`skeleton-${i}`} className="hover:bg-transparent">
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <Skeleton className="h-2.5 w-2.5 rounded-full" />
                      <Skeleton className="h-4 w-32" />
                    </div>
                  </TableCell>
                  <TableCell className="hidden md:table-cell">
                    <Skeleton className="h-4 w-12" />
                  </TableCell>
                  <TableCell className="hidden lg:table-cell">
                    <Skeleton className="h-4 w-10" />
                  </TableCell>
                  <TableCell>
                    <Skeleton className="h-5 w-20 rounded-full" />
                  </TableCell>
                  <TableCell className="hidden sm:table-cell">
                    <Skeleton className="h-4 w-24" />
                  </TableCell>
                  <TableCell>
                    <Skeleton className="h-8 w-28" />
                  </TableCell>
                  <TableCell className="hidden xl:table-cell">
                    <Skeleton className="h-4 w-20" />
                  </TableCell>
                </TableRow>
              ))
            : rows.map((report) => {
                const sla = slaLabel(report, now);
                const isSelected = report.id === selectedId;
                return (
                  <TableRow
                    key={report.id}
                    tabIndex={0}
                    role="button"
                    aria-label={`Open details for ${report.id} — ${report.category}`}
                    aria-pressed={isSelected}
                    data-state={isSelected ? "selected" : undefined}
                    onClick={(e) => activate(e, report.id)}
                    onKeyDown={(e) => activate(e, report.id)}
                    className={cn(
                      "cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--focus-ring)]",
                      isSelected && "bg-[var(--sidebar)]"
                    )}
                  >
                    <TableCell>
                      <div className="flex items-start gap-2">
                        <PriorityDot
                          priority={report.priority}
                          className="mt-1.5"
                        />
                        <div className="min-w-0">
                          <p className="font-semibold text-ink-primary">
                            {report.id}
                          </p>
                          <p className="truncate text-xs text-ink-secondary">
                            {report.category}
                          </p>
                        </div>
                      </div>
                    </TableCell>
                    <TableCell className="hidden md:table-cell">
                      Sector {report.sector}
                    </TableCell>
                    <TableCell className="hidden lg:table-cell">
                      {report.subsector}
                    </TableCell>
                    <TableCell>
                      <StatusBadge status={report.status} />
                    </TableCell>
                    <TableCell className="hidden whitespace-nowrap text-ink-secondary sm:table-cell">
                      {formatClock(report.reportedAt)} ·{" "}
                      {report.reportedAt.slice(0, 10)}
                    </TableCell>
                    <TableCell>
                      {report.assignee ? (
                        <div className="flex items-center gap-2">
                          <Avatar className="h-7 w-7">
                            <AvatarFallback>
                              {initials(report.assignee)}
                            </AvatarFallback>
                          </Avatar>
                          <span className="whitespace-nowrap text-sm">
                            {report.assignee}
                          </span>
                        </div>
                      ) : (
                        <span className="text-sm italic text-ink-secondary">
                          Unassigned
                        </span>
                      )}
                    </TableCell>
                    <TableCell
                      className={cn(
                        "hidden whitespace-nowrap text-xs font-semibold xl:table-cell",
                        sla.breached ? "text-[var(--error-text)]" : "text-ink-secondary"
                      )}
                    >
                      <span aria-label={sla.text}>{sla.text}</span>
                    </TableCell>
                  </TableRow>
                );
              })}
        </TableBody>
      </Table>
    </div>
  );
}
