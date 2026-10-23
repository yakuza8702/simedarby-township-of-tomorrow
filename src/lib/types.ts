// P2-SPEC §2 — shared TypeScript type definitions.

export type ReportCategory =
  | "Bin overflowing"
  | "Illegal dumping"
  | "Missed collection"
  | "Damaged bin"
  | "Recycling contamination"
  | "Street litter hotspot";

export type ReportPriority = "High" | "Medium" | "Low";
export type ReportStatus = "Open" | "In review" | "In Progress" | "Resolved";

export interface ReportEvent {
  status: ReportStatus | "Received" | "Acknowledged";
  at: string; // ISO 8601
  by: string;
}

export interface Report {
  id: string; // RPT-####, zero-padded 4 digits
  category: ReportCategory;
  priority: ReportPriority;
  sector: 1 | 3 | 5 | 7;
  subsector: number; // 1..N
  status: ReportStatus;
  reportedAt: string; // ISO 8601; October 2026
  assignee: string | null; // name or null when unassigned
  description: string;
  citizenName: string;
  citizenPhotoUrl?: string;
  gps: { lat: number; lng: number };
  slaHours: number; // e.g. 12 / 24
  slaStartedAt: string; // ISO 8601
  notes: string[];
  timeline: ReportEvent[];
}

export type RoleName = "Admin" | "Agent" | "Agent+" | "Viewer";

export type SectorRange = { from: number; to: number };
// "Read-only" reconciles §2's ScopeType with §3c's P. Ndiaye row (scope column).
export type ScopeType = "All sectors" | "Read-only" | SectorRange;

export type Permission =
  | "Full access"
  | "Edit+Assign"
  | "Edit+Assign+SLA"
  | "Read-only View";

export interface RoleMember {
  id: string;
  fullName: string;
  email: string;
  role: RoleName;
  scope: ScopeType;
  permissions: Permission;
  initials: string;
  avatarColor: string;
}

export type AuditAction =
  | "Updated SLA"
  | "Assigned"
  | "Escalated"
  | "Edited template"
  | "Resolved"
  | "Changed role"
  | "Created"
  | "Deleted";

export type AuditEntity =
  | { kind: "Report"; id: string }
  | { kind: "Template"; id: string }
  | { kind: "Role"; userId: string }
  | { kind: "SLA"; id: string };

export interface AuditEntry {
  id: string;
  time: string; // ISO 8601
  actor: string;
  action: AuditAction;
  entity: AuditEntity;
  before: string; // human-readable previous state
  after: string; // human-readable new state
}

export type BroadcastChannel = "SMS" | "Email" | "Push";
export type BroadcastAudience =
  | "All residents"
  | "Sub-sector 3"
  | "State agencies"; // audience misspelling from the design source corrected (INFERRED #5)

export interface Broadcast {
  id: string;
  channel: BroadcastChannel;
  title: string;
  body: string;
  audience: BroadcastAudience[];
  templateId: string;
  scheduledFor?: string; // ISO 8601, undefined = send now
  createdAt: string; // ISO 8601
  recipients: number;
  status: "Sent" | "Scheduled";
}

export interface AdminUser {
  id: string;
  fullName: string;
  email: string;
  role: RoleName;
  scope: ScopeType;
  initials: string;
  avatarColor: string;
}

/** Lightweight resolved-lifetime sample used only for the KPI aggregate (INFERRED #10). */
export interface ResolvedSample {
  id: string;
  sector: 1 | 3 | 5 | 7;
  resolvedAt: string;
}

export interface BroadcastTemplate {
  id: string;
  name: string;
  channel: BroadcastChannel;
  version: number;
  body: string;
}
