import { formatDuration, frozenNow } from "./mock-delay";
import type { Report } from "./types";

export function slaDeadlineMs(report: Report): number {
  return (
    new Date(report.slaStartedAt).getTime() + report.slaHours * 3_600_000
  );
}

export function slaRemainingMs(
  report: Report,
  nowMs: number = frozenNow().getTime()
): number {
  return slaDeadlineMs(report) - nowMs;
}

export function slaLabel(
  report: Report,
  nowMs: number = frozenNow().getTime()
): { text: string; breached: boolean } {
  const remaining = slaRemainingMs(report, nowMs);
  if (remaining >= 0) {
    return { text: `SLA · ${formatDuration(remaining)} left`, breached: false };
  }
  return {
    text: `SLA · ${formatDuration(remaining)} overdue (breached)`,
    breached: true,
  };
}
