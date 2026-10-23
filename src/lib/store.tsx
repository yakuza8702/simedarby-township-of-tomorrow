"use client";

// In-memory mutable store over the dummy data (standalone site — no backend).
// Mounted once in the (shell) layout; every mutation also appends an audit row.
import * as React from "react";

import { auditEntries as seedAudit } from "./data/audit";
import { broadcasts as seedBroadcasts } from "./data/broadcasts";
import { reports as seedReports } from "./data/reports";
import { currentUser as seedUser, roleMembers as seedMembers } from "./data/roles";
import { formatNaiveLocal, frozenNowTick } from "./mock-delay";
import type {
  AdminUser,
  AuditAction,
  AuditEntry,
  Broadcast,
  Report,
  ReportStatus,
  RoleMember,
  ScopeType,
} from "./types";

export interface EscalationMap {
  [reportId: string]: number; // 1 = Level 1 (default), 2+ = escalated
}

interface StoreValue {
  reports: Report[];
  roleMembers: RoleMember[];
  auditEntries: AuditEntry[];
  broadcasts: Broadcast[];
  currentUser: AdminUser;
  escalations: EscalationMap;
  /** Permission-denied demo: preview the console as the Viewer role. */
  viewAsViewer: boolean;
  setViewAsViewer: (v: boolean) => void;
  getReport: (id: string) => Report | undefined;
  addNote: (reportId: string, note: string) => void;
  assignReport: (reportId: string, assignee: string) => void;
  escalateReport: (reportId: string) => void;
  closeReport: (reportId: string) => void;
  updateRoleMember: (
    id: string,
    patch: Pick<RoleMember, "role" | "scope" | "permissions">
  ) => void;
  appendBroadcast: (broadcast: Broadcast) => void;
}

const StoreContext = React.createContext<StoreValue | null>(null);

function nextAuditId(existing: AuditEntry[]): string {
  const max = existing.reduce((acc, e) => {
    const n = Number(e.id.replace(/\D/g, ""));
    return Number.isFinite(n) && n > acc ? n : acc;
  }, 0);
  return `AUD-${String(max + 1).padStart(3, "0")}`;
}

function scopeLabel(scope: ScopeType): string {
  return typeof scope === "string" ? scope : `Sector ${scope.from}–${scope.to}`;
}

function makeAudit(
  existing: AuditEntry[],
  actor: string,
  action: AuditAction,
  entity: AuditEntry["entity"],
  before: string,
  after: string
): AuditEntry {
  return {
    id: nextAuditId(existing),
    // Frozen-clock stamp (naive local, seed style) — never the real wall clock.
    time: formatNaiveLocal(frozenNowTick()),
    actor,
    action,
    entity,
    before,
    after,
  };
}

export function StoreProvider({ children }: { children: React.ReactNode }) {
  const [reports, setReports] = React.useState<Report[]>(() =>
    seedReports.map((r) => ({ ...r, notes: [...r.notes], timeline: [...r.timeline] }))
  );
  const [roleMembers, setRoleMembers] = React.useState<RoleMember[]>(() =>
    seedMembers.map((m) => ({ ...m }))
  );
  const [auditEntries, setAuditEntries] = React.useState<AuditEntry[]>(() => [
    ...seedAudit,
  ]);
  const [broadcasts, setBroadcasts] = React.useState<Broadcast[]>(() => [
    ...seedBroadcasts,
  ]);
  const [escalations, setEscalations] = React.useState<EscalationMap>({});
  const [viewAsViewer, setViewAsViewer] = React.useState(false);

  const pushAudit = React.useCallback(
    (actor: string, action: AuditAction, entity: AuditEntry["entity"], before: string, after: string) => {
      setAuditEntries((prev) => [
        makeAudit(prev, actor, action, entity, before, after),
        ...prev,
      ]);
    },
    []
  );

  const value = React.useMemo<StoreValue>(() => {
    const effectiveRole: AdminUser = viewAsViewer
      ? { ...seedUser, role: "Viewer", scope: "Read-only" }
      : seedUser;

    return {
      reports,
      roleMembers,
      auditEntries,
      broadcasts,
      currentUser: effectiveRole,
      escalations,
      viewAsViewer,
      setViewAsViewer,
      getReport: (id) => reports.find((r) => r.id === id),
      addNote: (reportId, note) => {
        const text = note.trim();
        if (!text) return;
        setReports((prev) =>
          prev.map((r) =>
            r.id === reportId ? { ...r, notes: [...r.notes, text] } : r
          )
        );
      },
      assignReport: (reportId, assignee) => {
        setReports((prev) =>
          prev.map((r) => {
            if (r.id !== reportId) return r;
            const nextStatus: ReportStatus =
              r.status === "Open" ? "In review" : r.status;
            const timeline = [...r.timeline];
            if (
              nextStatus === "In review" &&
              !timeline.some((e) => e.status === "Acknowledged")
            ) {
              timeline.push({
                status: "Acknowledged",
                at: formatNaiveLocal(frozenNowTick()),
                by: assignee,
              });
            }
            return { ...r, assignee, status: nextStatus, timeline };
          })
        );
        const target = reports.find((r) => r.id === reportId);
        pushAudit(
          seedUser.fullName,
          "Assigned",
          { kind: "Report", id: reportId },
          target?.assignee ?? "Unassigned",
          assignee
        );
      },
      escalateReport: (reportId) => {
        setEscalations((prev) => {
          const current = prev[reportId] ?? 1;
          return { ...prev, [reportId]: current + 1 };
        });
        const current = escalations[reportId] ?? 1;
        pushAudit(
          seedUser.fullName,
          "Escalated",
          { kind: "Report", id: reportId },
          `Level ${current}`,
          `Level ${current + 1}`
        );
      },
      closeReport: (reportId) => {
        setReports((prev) =>
          prev.map((r) => {
            if (r.id !== reportId) return r;
            const timeline = [...r.timeline];
            if (!timeline.some((e) => e.status === "In Progress")) {
              timeline.push({
                status: "In Progress",
                at: formatNaiveLocal(frozenNowTick()),
                by: seedUser.fullName,
              });
            }
            timeline.push({
              status: "Resolved",
              at: formatNaiveLocal(frozenNowTick()),
              by: seedUser.fullName,
            });
            return { ...r, status: "Resolved", timeline };
          })
        );
        const target = reports.find((r) => r.id === reportId);
        pushAudit(
          seedUser.fullName,
          "Resolved",
          { kind: "Report", id: reportId },
          target?.status ?? "Open",
          "Resolved"
        );
      },
      updateRoleMember: (id, patch) => {
        setRoleMembers((prev) =>
          prev.map((m) => (m.id === id ? { ...m, ...patch } : m))
        );
        const target = roleMembers.find((m) => m.id === id);
        // K6: when an editable field actually changed, the audit strings carry
        // the full role · scope · permissions state; a no-op save keeps the
        // plain role-only strings (row still appended, as before).
        const changed =
          target?.role !== patch.role ||
          target?.permissions !== patch.permissions ||
          JSON.stringify(target?.scope) !== JSON.stringify(patch.scope);
        const before = target
          ? changed
            ? `${target.role} · ${scopeLabel(target.scope)} · ${target.permissions}`
            : target.role
          : "—";
        const after = changed
          ? `${patch.role} · ${scopeLabel(patch.scope)} · ${patch.permissions}`
          : patch.role;
        pushAudit(
          seedUser.fullName,
          "Changed role",
          { kind: "Role", userId: id },
          before,
          after
        );
      },
      appendBroadcast: (broadcast) => {
        setBroadcasts((prev) => [broadcast, ...prev]);
      },
    };
  }, [
    reports,
    roleMembers,
    auditEntries,
    broadcasts,
    escalations,
    viewAsViewer,
    pushAudit,
  ]);

  return (
    <StoreContext.Provider value={value}>{children}</StoreContext.Provider>
  );
}

export function useStore(): StoreValue {
  const ctx = React.useContext(StoreContext);
  if (!ctx) throw new Error("useStore must be used inside <StoreProvider>");
  return ctx;
}
