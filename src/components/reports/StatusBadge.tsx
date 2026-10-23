import { Badge } from "@/components/ui/badge";
import { cn } from "@/components/ui/utils";
import type { ReportStatus } from "@/lib/types";

const STATUS_STYLES: Record<ReportStatus, string> = {
  Open: "bg-[var(--chip-amber-bg)] text-[var(--chip-amber-text)]",
  "In review": "bg-[var(--chip-blue-bg)] text-[var(--chip-blue-text)]",
  "In Progress": "bg-[var(--chip-amber-bg)] text-[var(--chip-amber-text)]",
  Resolved: "bg-[var(--chip-green-bg)] text-[var(--chip-green-text)]",
};

export function StatusBadge({
  status,
  className,
}: {
  status: ReportStatus;
  className?: string;
}) {
  return (
    <Badge
      aria-label={`Status: ${status}`}
      className={cn(
        "rounded-full px-2.5 py-0.5 text-xs font-semibold",
        STATUS_STYLES[status],
        className
      )}
    >
      {status}
    </Badge>
  );
}
