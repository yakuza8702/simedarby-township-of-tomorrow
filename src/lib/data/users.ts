// Task B — /users dummy data: council staff accounts, roles and access
// review. Reuses the RolesTable roster (lib/data/roles.ts — the same 5
// members Settings → Roles edits) and layers on last-active stamps plus a
// per-resource permission matrix, both INFERRED for the access review.

import { roleMembers } from "./roles";
import type { Permission, RoleMember, RoleName } from "../types";

export { roleMembers };

export interface UserActivity {
  userId: string;
  /** ISO 8601, October 2026 (frozen console clock). */
  lastActiveAt: string;
  lastAction: string;
}

/** Last-active stamps for the 5 roster members (INFERRED). */
export const USER_ACTIVITY: UserActivity[] = [
  {
    userId: "USR-001",
    lastActiveAt: "2026-10-23T17:58:00",
    lastAction: "Updated SLA on RPT-2481",
  },
  {
    userId: "USR-002",
    lastActiveAt: "2026-10-23T16:42:00",
    lastAction: "Assigned RPT-2403 to crew CR-03",
  },
  {
    userId: "USR-003",
    lastActiveAt: "2026-10-23T15:10:00",
    lastAction: "Moved RPT-2425 to In review",
  },
  {
    userId: "USR-004",
    lastActiveAt: "2026-10-22T11:26:00",
    lastAction: "Viewed audit log",
  },
  {
    userId: "USR-005",
    lastActiveAt: "2026-10-23T14:05:00",
    lastAction: "Closed RPT-2416",
  },
];

export const CONSOLE_RESOURCES = [
  "Reports queue",
  "Sectors",
  "Collection routes",
  "Broadcast",
  "Audit log",
  "SLA policies",
] as const;

export type ConsoleResource = (typeof CONSOLE_RESOURCES)[number];

/**
 * Per-resource permission chips per editable Permission value — the
 * access-review matrix (F5). Keyed by the Permission field RolesTable writes
 * (NOT by member id), so there is a single source: a member's chips compose
 * at read time from their own `permissions`, and the role matrix is just the
 * same table read through the role's default permission. Viewer sees Read
 * everywhere; Admin has Full access; Agent / Agent+ edit the operational
 * resources but not SLA policies (Agent+ does, per §3c).
 */
const PERMISSION_MATRIX: Record<
  Permission,
  Record<ConsoleResource, string>
> = {
  "Full access": {
    "Reports queue": "Full access",
    Sectors: "Full access",
    "Collection routes": "Full access",
    Broadcast: "Full access",
    "Audit log": "Full access",
    "SLA policies": "Full access",
  },
  "Edit+Assign+SLA": {
    "Reports queue": "Edit+Assign+SLA",
    Sectors: "Edit",
    "Collection routes": "Edit",
    Broadcast: "Compose",
    "Audit log": "View",
    "SLA policies": "Edit",
  },
  "Edit+Assign": {
    "Reports queue": "Edit+Assign",
    Sectors: "View",
    "Collection routes": "Edit",
    Broadcast: "View",
    "Audit log": "View",
    "SLA policies": "No access",
  },
  "Read-only View": {
    "Reports queue": "Read-only View",
    Sectors: "Read-only View",
    "Collection routes": "Read-only View",
    Broadcast: "Read-only View",
    "Audit log": "Read-only View",
    "SLA policies": "No access",
  },
};

/** Permission an unedited member of each role holds (P2-SPEC §3c). */
const ROLE_DEFAULT_PERMISSION: Record<RoleName, Permission> = {
  Admin: "Full access",
  "Agent+": "Edit+Assign+SLA",
  Agent: "Edit+Assign",
  Viewer: "Read-only View",
};

/** Role-level default chips (seed parity — same matrix as before F5). */
export function resourcePermission(
  role: RoleName,
  resource: ConsoleResource
): string {
  return PERMISSION_MATRIX[ROLE_DEFAULT_PERMISSION[role]][resource];
}

/**
 * Per-resource permission for ONE member (F5): reads the member's editable
 * `permissions` field (the one RolesTable writes — same field the preview
 * modal's "Permissions" row shows), falling back to the role default only
 * when that field is empty/undefined.
 */
export function memberResourcePermission(
  member: { role: RoleName; permissions?: Permission | string | null },
  resource: ConsoleResource
): string {
  const raw =
    typeof member.permissions === "string" ? member.permissions.trim() : "";
  const permission: Permission =
    raw !== "" && raw in PERMISSION_MATRIX
      ? (raw as Permission)
      : ROLE_DEFAULT_PERMISSION[member.role];
  return PERMISSION_MATRIX[permission][resource];
}

/** Chip tone per permission string (dark-ready token classes). */
export function permissionChipClass(permission: string): string {
  if (permission === "No access")
    return "border-[var(--border-plain)] bg-[var(--input-bg)] text-ink-secondary";
  if (permission.startsWith("Read-only") || permission === "View")
    return "border-[var(--border-plain)] bg-[var(--surface)] text-ink-secondary";
  if (permission.includes("SLA") || permission === "Full access")
    return "border-[var(--chip-green-border)] bg-[var(--chip-green-bg)] text-[var(--green-text)]";
  return "border-[var(--chip-blue-border)] bg-[var(--chip-blue-bg)] text-[var(--chip-blue-text)]";
}

/** Access-review role counts (Admin 1 / Agent+ 1 / Agent 2 / Viewer 1). */
export const ROLE_COUNTS: Array<{ role: RoleName; count: number; permission: Permission }> = (
  ["Admin", "Agent+", "Agent", "Viewer"] as RoleName[]
).map((role) => {
  const members = roleMembers.filter((m) => m.role === role);
  const permission = members[0]?.permissions ?? "Read-only View";
  return { role, count: members.length, permission };
});

/**
 * Live header totals derived from the CURRENT members array (F4): pass
 * store.roleMembers so staff/admin counts recompute after role edits. Seed
 * parity — deriveUserTotals(roleMembers) renders the same hero copy numbers
 * as before ("5 council staff · 1 admin · 4 active today").
 */
export function deriveUserTotals(members: RoleMember[]): {
  staff: number;
  admins: number;
  activeToday: number;
} {
  const ids = new Set(members.map((m) => m.id));
  return {
    staff: members.length,
    admins: members.filter((m) => m.role === "Admin").length,
    activeToday: USER_ACTIVITY.filter(
      (a) => ids.has(a.userId) && a.lastActiveAt.startsWith("2026-10-23")
    ).length,
  };
}

/** Seed-roster totals (static snapshot; page uses deriveUserTotals instead). */
export const USER_TOTALS = deriveUserTotals(roleMembers);
