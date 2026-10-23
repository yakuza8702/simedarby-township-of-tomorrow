"use client";

// P2-SPEC §6 — report detail drawer (Sheet, right, 380px) with timeline,
// SLA countdown, internal notes and Assign / Escalate / Close actions.
import * as React from "react";

import { formatClock, formatDuration, frozenNow } from "@/lib/mock-delay";
import { slaDeadlineMs } from "@/lib/sla";
import { useStore } from "@/lib/store";
import type { Report, ReportEvent } from "@/lib/types";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Textarea } from "@/components/ui/textarea";
import { useToast } from "@/components/ui/use-toast";
import { PriorityDot } from "./PriorityDot";
import { StatusBadge } from "./StatusBadge";

const TIMELINE_STEPS: Array<{ key: ReportEvent["status"]; label: string }> = [
  { key: "Received", label: "Received" },
  { key: "Acknowledged", label: "Acknowledged" },
  { key: "In Progress", label: "In Progress" },
  { key: "Resolved", label: "Resolved" },
];

function initials(name: string): string {
  return name
    .replace(".", "")
    .split(" ")
    .map((p) => p[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();
}

interface DetailDrawerProps {
  reportId: string | null;
  onClose: () => void;
}

export function DetailDrawer({ reportId, onClose }: DetailDrawerProps) {
  const store = useStore();
  const { toast } = useToast();
  const report = reportId ? store.getReport(reportId) : undefined;

  // Ticking now on top of the frozen clock: mount offset + real elapsed time.
  const [elapsedMs, setElapsedMs] = React.useState(0);
  React.useEffect(() => {
    const started = Date.now();
    const id = window.setInterval(
      () => setElapsedMs(Date.now() - started),
      10_000
    );
    return () => window.clearInterval(id);
  }, []);
  const nowMs = frozenNow().getTime() + elapsedMs;

  const [noteDraft, setNoteDraft] = React.useState("");

  React.useEffect(() => {
    setNoteDraft("");
  }, [reportId]);

  const escalationLevel = reportId ? store.escalations[reportId] ?? 1 : 1;

  const slaText = report
    ? (() => {
        const remaining = slaDeadlineMs(report) - nowMs;
        if (remaining >= 0) {
          return {
            text: `SLA · ${formatDuration(remaining)} left`,
            breached: false,
          };
        }
        return {
          text: `SLA · ${formatDuration(remaining)} overdue (breached)`,
          breached: true,
        };
      })()
    : null;

  return (
    <Sheet
      open={Boolean(reportId)}
      onOpenChange={(open) => {
        if (!open) onClose();
      }}
    >
      <SheetContent
        aria-describedby={report ? "report-drawer-meta" : undefined}
        className="flex h-full flex-col gap-0 p-0"
      >
        {!report ? (
          <div className="flex h-full items-center justify-center p-6 text-sm text-ink-secondary">
            Select a report to view details.
          </div>
        ) : (
          <>
            <div className="panel-scroll flex-1 overflow-y-auto">
              <SheetHeader className="border-b border-[var(--border-plain)] p-5">
                <div className="flex items-center gap-2">
                  <StatusBadge status={report.status} />
                  <PriorityDot priority={report.priority} />
                  {escalationLevel > 1 ? (
                    <span className="rounded-full bg-[var(--chip-red-bg)] px-2 py-0.5 text-xs font-semibold text-[var(--chip-red-text)]">
                      Level {escalationLevel} escalation
                    </span>
                  ) : null}
                </div>
                <SheetTitle className="pt-1 text-xl">
                  {report.id} — {report.category}
                </SheetTitle>
                <SheetDescription id="report-drawer-meta">
                  {report.category} · Reported {formatClock(report.reportedAt)}{" "}
                  · Sub-sector {report.subsector}
                </SheetDescription>
                {/* K5: no aria-live on the ticking countdown; the breach state
                    change is announced once via the live region below. */}
                <p
                  className={
                    slaText?.breached
                      ? "pt-1 text-sm font-semibold text-[var(--error-text)]"
                      : "pt-1 text-sm font-semibold text-ink-tertiary"
                  }
                >
                  {slaText?.text}
                </p>
                {slaText?.breached ? (
                  <p role="status" aria-live="polite" className="sr-only">
                    {slaText.text}
                  </p>
                ) : null}
              </SheetHeader>

              <div className="space-y-5 p-5">
                <section aria-label="Description">
                  <h4 className="text-xs font-semibold uppercase tracking-wide text-ink-secondary">
                    Description
                  </h4>
                  <p className="mt-1.5 text-sm text-ink-primary">
                    {report.description}
                  </p>
                </section>

                <section aria-label="Timeline">
                  <h4 className="text-xs font-semibold uppercase tracking-wide text-ink-secondary">
                    Timeline
                  </h4>
                  <ol className="mt-2 space-y-0">
                    {TIMELINE_STEPS.map((step, i) => {
                      const event = report.timeline.find(
                        (e) => e.status === step.key
                      );
                      const done = Boolean(event);
                      const last = i === TIMELINE_STEPS.length - 1;
                      return (
                        <li key={step.key} className="relative flex gap-3 pb-4">
                          {!last ? (
                            <span
                              aria-hidden="true"
                              className={
                                done
                                  ? "absolute left-[7px] top-4 h-full w-px bg-[#2E7D32]"
                                  : "absolute left-[7px] top-4 h-full w-px bg-[var(--border-plain)]"
                              }
                            />
                          ) : null}
                          <span
                            aria-hidden="true"
                            className={
                              done
                                ? "relative z-10 mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-[#2E7D32] ring-2 ring-[var(--surface)]"
                                : "relative z-10 mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-full border-2 border-[var(--border-plain)] bg-[var(--surface)]"
                            }
                          />
                          <div className="min-w-0 -mt-0.5">
                            <p
                              className={
                                done
                                  ? "text-sm font-medium text-ink-primary"
                                  : "text-sm font-medium text-ink-secondary"
                              }
                            >
                              {step.label}
                              {!done ? (
                                <span className="ml-2 text-xs font-normal">
                                  (pending)
                                </span>
                              ) : null}
                            </p>
                            {event ? (
                              <p className="text-xs text-ink-secondary">
                                {formatClock(event.at)} · {event.at.slice(0, 10)}{" "}
                                · by {event.by}
                              </p>
                            ) : null}
                          </div>
                        </li>
                      );
                    })}
                  </ol>
                </section>

                <section
                  aria-label="Citizen and location"
                  className="rounded-[12px] border border-[var(--border-plain)] bg-[var(--input-bg)] p-3"
                >
                  <div className="flex items-center gap-3">
                    <Avatar>
                      <AvatarFallback>
                        {initials(report.citizenName)}
                      </AvatarFallback>
                    </Avatar>
                    <div>
                      <p className="text-sm font-semibold text-ink-primary">
                        {report.citizenName}
                      </p>
                      <p className="text-xs text-ink-secondary">
                        Resident · Sector {report.sector}
                      </p>
                    </div>
                  </div>
                  <p className="mt-2 text-xs text-ink-secondary">
                    GPS · {report.gps.lat.toFixed(4)},{" "}
                    {report.gps.lng.toFixed(4)} · Sub-sector {report.subsector}
                  </p>
                </section>

                <section aria-label="Internal notes">
                  <h4 className="text-xs font-semibold uppercase tracking-wide text-ink-secondary">
                    Internal notes
                  </h4>
                  {report.notes.length > 0 ? (
                    <ul className="mt-2 space-y-1.5">
                      {report.notes.map((note, i) => (
                        <li
                          key={`${report.id}-note-${i}`}
                          className="rounded-[8px] border border-[var(--border-plain)] bg-[var(--surface)] px-3 py-2 text-sm text-ink-primary"
                        >
                          {note}
                        </li>
                      ))}
                    </ul>
                  ) : (
                    <p className="mt-2 text-xs italic text-ink-secondary">
                      No notes yet — share context with the response team.
                    </p>
                  )}
                  <div className="mt-2 space-y-2">
                    <Label htmlFor="internal-note" className="sr-only">
                      Add an internal note
                    </Label>
                    <Textarea
                      id="internal-note"
                      placeholder="Add a note for the response team…"
                      className="min-h-[72px]"
                      value={noteDraft}
                      onChange={(e) => setNoteDraft(e.target.value)}
                    />
                    <Button
                      variant="outline"
                      size="sm"
                      disabled={!noteDraft.trim()}
                      onClick={() => {
                        store.addNote(report.id, noteDraft);
                        setNoteDraft("");
                        toast({
                          title: "Note added",
                          description: `Internal note saved on ${report.id}.`,
                        });
                      }}
                    >
                      Add note
                    </Button>
                  </div>
                </section>
              </div>
            </div>

            <div className="grid grid-cols-3 gap-2 border-t border-[var(--border-plain)] bg-[var(--surface)] p-4">
              <Popover>
                <PopoverTrigger asChild>
                  <Button
                    variant="outline"
                    size="sm"
                    className="w-full"
                    aria-label={`Assign ${report.id}`}
                  >
                    Assign
                  </Button>
                </PopoverTrigger>
                <PopoverContent
                  align="start"
                  side="top"
                  className="w-64 p-2"
                  aria-label="Assign to team member"
                >
                  <p className="px-2 pb-1.5 text-xs font-semibold uppercase tracking-wide text-ink-secondary">
                    Assign to
                  </p>
                  <ul className="flex flex-col gap-0.5">
                    {store.roleMembers
                      .filter((m) => m.role !== "Viewer")
                      .map((member) => (
                        <li key={member.id}>
                          <button
                            type="button"
                            className="flex w-full items-center gap-2 rounded-[6px] px-2 py-1.5 text-left text-sm hover:bg-[var(--sidebar)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--focus-ring)]"
                            onClick={() => {
                              store.assignReport(report.id, member.fullName);
                              toast({
                                title: "Report assigned",
                                description: `${report.id} → ${member.fullName}.`,
                                variant: "success",
                              });
                            }}
                          >
                            <Avatar className="h-6 w-6">
                              <AvatarFallback className="text-[10px]">
                                {member.initials}
                              </AvatarFallback>
                            </Avatar>
                            <span className="min-w-0 flex-1 truncate">
                              {member.fullName}
                            </span>
                            <span className="shrink-0 text-xs text-ink-secondary">
                              {member.role}
                            </span>
                          </button>
                        </li>
                      ))}
                  </ul>
                </PopoverContent>
              </Popover>

              <Button
                variant="outline"
                size="sm"
                className="w-full border-[var(--chip-amber-border)] bg-[var(--chip-amber-bg)] text-[var(--chip-amber-text)] hover:bg-[var(--chip-amber-bg)]"
                onClick={() => {
                  store.escalateReport(report.id);
                  toast({
                    title: "Escalated",
                    description: `${report.id} moved to Level ${
                      escalationLevel + 1
                    }.`,
                    variant: "warning",
                  });
                }}
                aria-label={`Escalate ${report.id}`}
              >
                Escalate
              </Button>

              <Button
                size="sm"
                className="w-full"
                disabled={report.status === "Resolved"}
                onClick={() => {
                  store.closeReport(report.id);
                  toast({
                    title: "Report resolved",
                    description: `${report.id} closed and logged to the audit trail.`,
                    variant: "success",
                  });
                }}
                aria-label={`Close ${report.id}`}
              >
                Close
              </Button>
            </div>
          </>
        )}
      </SheetContent>
    </Sheet>
  );
}
