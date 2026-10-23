// P2-SPEC §3c — role members + the signed-in admin user.
import type { AdminUser, RoleMember } from "../types";

export const roleMembers: RoleMember[] = [
  {
    id: "USR-001",
    fullName: "A. Rahman",
    email: "admin@township.example",
    role: "Admin",
    scope: "All sectors",
    permissions: "Full access",
    initials: "AR",
    avatarColor: "#E8F5E9",
  },
  {
    id: "USR-002",
    fullName: "M. Alvarez",
    email: "m.alvarez@township.example",
    role: "Agent",
    scope: { from: 1, to: 3 },
    permissions: "Edit+Assign",
    initials: "MA",
    avatarColor: "#E8F5E9",
  },
  {
    id: "USR-003",
    fullName: "J. Okafor",
    email: "j.okafor@township.example",
    role: "Agent+",
    scope: { from: 3, to: 3 },
    permissions: "Edit+Assign+SLA",
    initials: "JO",
    avatarColor: "#E8F5E9",
  },
  {
    id: "USR-004",
    fullName: "P. Ndiaye",
    email: "p.ndiaye@township.example",
    role: "Viewer",
    scope: "Read-only",
    permissions: "Read-only View",
    initials: "PN",
    avatarColor: "#E8F5E9",
  },
  {
    id: "USR-005",
    fullName: "L. Chen",
    email: "l.chen@township.example",
    role: "Agent",
    scope: { from: 5, to: 7 },
    permissions: "Edit+Assign",
    initials: "LC",
    avatarColor: "#E8F5E9",
  },
];

/** The single hardcoded console admin (P2-SPEC §6 login flow). */
export const currentUser: AdminUser = {
  id: "USR-001",
  fullName: "A. Rahman",
  email: "admin@township.example",
  role: "Admin",
  scope: "All sectors",
  initials: "AR",
  avatarColor: "#E8F5E9",
};

export const DEMO_CREDENTIALS = {
  email: "admin@township.example",
  password: "council2026",
} as const;

/** Audience reach numbers for the broadcast composer (INFERRED). */
export const AUDIENCE_REACH: Record<string, number> = {
  "All residents": 12480,
  "Sub-sector 3": 1860,
  "State agencies": 14,
};

/** SLA policy table (Settings → SLA policies panel). */
export const slaPolicies = [
  { priority: "High", firstResponse: "12h", resolution: "48h", escalation: "Level 2 after breach" },
  { priority: "Medium", firstResponse: "24h", resolution: "72h", escalation: "Level 1 after breach" },
  { priority: "Low", firstResponse: "24h", resolution: "7d", escalation: "Queue review" },
] as const;
