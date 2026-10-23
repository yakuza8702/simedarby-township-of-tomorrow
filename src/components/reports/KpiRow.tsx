import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/components/ui/utils";

interface Kpi {
  label: string;
  value: string;
  footnote?: string;
}

// V1 — 4px left accent bar per KPI (design tokens).
const ACCENT: Record<string, string> = {
  "Open reports": "border-l-4 border-l-[#F9A825]",
  "In review": "border-l-4 border-l-[#1E88E5]",
  "Resolved this week": "border-l-4 border-l-[#388E3C]",
  "Avg first response": "border-l-4 border-l-[var(--ink-primary)]",
};

export function KpiRow({ kpis }: { kpis: Kpi[] }) {
  return (
    <section
      aria-label="Queue overview"
      className="grid grid-cols-2 gap-3 sm:gap-4 xl:grid-cols-4"
    >
      {kpis.map((kpi) => (
        <Card
          key={kpi.label}
          className={cn("rounded-[12px]", ACCENT[kpi.label])}
        >
          <CardContent className="p-4 sm:p-5">
            <p className="text-xs font-semibold uppercase tracking-wide text-ink-secondary">
              {kpi.label}
            </p>
            <p className="mt-1.5 text-2xl font-bold text-ink-primary">
              {kpi.value}
            </p>
            {kpi.footnote ? (
              <p className="mt-1 text-xs text-ink-secondary">{kpi.footnote}</p>
            ) : null}
          </CardContent>
        </Card>
      ))}
    </section>
  );
}
