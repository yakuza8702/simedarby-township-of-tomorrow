import { cn } from "@/components/ui/utils";
import type { ReportPriority } from "@/lib/types";

// V4 — priority CHIP (pill) instead of a bare dot.
const PRIORITY_CHIP: Record<ReportPriority, string> = {
  High: "bg-[#B71C1C] text-white",
  Medium: "bg-[var(--chip-amber-bg)] text-[var(--chip-amber-text)]",
  Low: "bg-[var(--chip-blue-bg)] text-[var(--chip-blue-strong)]",
};

export function PriorityDot({
  priority,
  className,
}: {
  priority: ReportPriority;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold",
        PRIORITY_CHIP[priority],
        className
      )}
    >
      {priority}
      <span className="sr-only">Priority: {priority}</span>
    </span>
  );
}
