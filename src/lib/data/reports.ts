// P2-SPEC §3 / §3a / §3b — October 2026 dummy reports.
//
// - 24 Open reports labelled RPT-2401..RPT-2424 (design hero: "24 open reports").
// - 9 In review reports RPT-2425..RPT-2433, reachable via the Status filter (§3b).
// - 61 lifetime resolved reports RPT-2301..RPT-2361 as a KPI-only sample (§3, INFERRED #10).
//
// Distribution (Open): High 6 · Medium 11 · Low 7 · Sector 1:7 Sector 3:6 Sector 5:6
// Sector 7:5 · Assigned 17 (of which 7 → A. Rahman, the current admin) ·
// Unassigned 7 · sub-sectors 1–9 · 2026-10-17..2026-10-23.
//
// RPT-2401 is crafted so that at the frozen now (2026-10-23T18:06) its SLA reads
// exactly "SLA · 14h 06m left" and its mini-card copy reads
// "RPT-2401 · Illegal dumping · 08:12" (design copy patterns, Appendix B).

import type {
  Report,
  ReportCategory,
  ReportEvent,
  ReportPriority,
  ReportStatus,
  ResolvedSample,
} from "../types";

export const CATEGORIES: ReportCategory[] = [
  "Bin overflowing",
  "Illegal dumping",
  "Missed collection",
  "Damaged bin",
  "Recycling contamination",
  "Street litter hotspot",
];

export const PRIORITIES: ReportPriority[] = ["High", "Medium", "Low"];
export const STATUSES: ReportStatus[] = ["Open", "In review", "In Progress", "Resolved"];
export const SECTORS: Array<1 | 3 | 5 | 7> = [1, 3, 5, 7];
export const SUBSECTORS = [1, 2, 3, 4, 5, 6, 7, 8, 9];

export const AVG_FIRST_RESPONSE_HOURS = "2.4h";

interface Seed {
  n: number;
  cat: ReportCategory;
  pri: ReportPriority;
  sector: 1 | 3 | 5 | 7;
  subsector: number;
  at: string; // ISO local, October 2026
  assignee: string | null;
  citizen: string;
  desc: string;
  slaHours?: number; // default by priority below
  status?: ReportStatus; // default "Open"
  notes?: string[];
}

const CITIZENS = [
  "Nurul Aisyah", "Daniel Cruz", "Fatimah Zahra", "Kwame Mensah", "Lucia Romero",
  "Rizal Hakim", "Amara Diallo", "Chen Wei", "Sofia Marchetti", "Ibrahim Musa",
  "Grace Mwangi", "Hafiz Rahman", "Elena Petrova", "Tariq Jamal", "Mei Ling",
  "Omar Farouk", "Priya Nair", "Jonas Berg", "Zainab Ali", "Marco Silva",
  "Ayesha Khan", "Peter Okoro", "Lina Tan", "Hassan Karim",
];

const DESCS: Record<ReportCategory, string[]> = {
  "Bin overflowing": [
    "Three bins at the hawker centre are overflowing since this morning; waste spilling onto the walkway.",
    "Recycling bin at the bus stop is full — bags stacked beside it attracting stray dogs.",
    "Community bin behind the market never collected this week; smell is getting strong.",
  ],
  "Illegal dumping": [
    "Construction rubble dumped overnight beside the river walkway.",
    "Someone dumped two sofas and a fridge at the back lane near the kopitiam.",
    "Used tyres piled up on the vacant lot; kids play around them after school.",
  ],
  "Missed collection": [
    "Truck skipped our street entirely on Tuesday's scheduled round.",
    "Recycling collection missed for the second week running on Jalan Melur.",
    "Green-waste pickup did not arrive although the app showed 'scheduled'.",
  ],
  "Damaged bin": [
    "Wheelie bin lid cracked after the lorry lifted it; rain gets in.",
    "Bin hinge broken and sharp edges exposed — unsafe for residents.",
    "Two-wheeled cart bin lost a wheel, cannot be moved by the crew.",
  ],
  "Recycling contamination": [
    "General waste spotted inside the blue recycling bin for the third day.",
    "Food waste and styrofoam dumped into the recycling container at Block C.",
    "Construction foam pieces in the recycling bin; crew had to reject the load.",
  ],
  "Street litter hotspot": [
    "Litter hotspot forming around the corner shop; cups and wrappers daily.",
    "Plastic bags caught in the drain grates after the weekend market.",
    "Food-court leftovers strewn along the five-foot way every evening.",
  ],
};

// n, category, priority, sector, subsector, reportedAt, assignee
const OPEN_SEEDS: Seed[] = [
  { n: 1, cat: "Illegal dumping", pri: "High", sector: 3, subsector: 3, at: "2026-10-23T08:12:00", assignee: "A. Rahman", citizen: CITIZENS[0], desc: DESCS["Illegal dumping"][0], slaHours: 24 },
  { n: 2, cat: "Bin overflowing", pri: "Medium", sector: 1, subsector: 2, at: "2026-10-23T09:40:00", assignee: "A. Rahman", citizen: CITIZENS[1], desc: DESCS["Bin overflowing"][0] },
  { n: 3, cat: "Missed collection", pri: "Medium", sector: 3, subsector: 3, at: "2026-10-23T11:05:00", assignee: "M. Alvarez", citizen: CITIZENS[2], desc: DESCS["Missed collection"][0] },
  { n: 4, cat: "Street litter hotspot", pri: "High", sector: 1, subsector: 1, at: "2026-10-22T07:50:00", assignee: "A. Rahman", citizen: CITIZENS[3], desc: DESCS["Street litter hotspot"][0], slaHours: 12 },
  { n: 5, cat: "Damaged bin", pri: "Medium", sector: 3, subsector: 4, at: "2026-10-22T10:22:00", assignee: null, citizen: CITIZENS[4], desc: DESCS["Damaged bin"][0] },
  { n: 6, cat: "Recycling contamination", pri: "Low", sector: 5, subsector: 5, at: "2026-10-22T12:48:00", assignee: "L. Chen", citizen: CITIZENS[5], desc: DESCS["Recycling contamination"][0] },
  { n: 7, cat: "Illegal dumping", pri: "High", sector: 1, subsector: 2, at: "2026-10-23T13:30:00", assignee: "A. Rahman", citizen: CITIZENS[6], desc: DESCS["Illegal dumping"][1], slaHours: 12 },
  { n: 8, cat: "Bin overflowing", pri: "Medium", sector: 3, subsector: 3, at: "2026-10-21T08:05:00", assignee: "J. Okafor", citizen: CITIZENS[7], desc: DESCS["Bin overflowing"][1] },
  { n: 9, cat: "Missed collection", pri: "Medium", sector: 5, subsector: 6, at: "2026-10-21T09:15:00", assignee: null, citizen: CITIZENS[8], desc: DESCS["Missed collection"][1] },
  { n: 10, cat: "Damaged bin", pri: "Low", sector: 7, subsector: 7, at: "2026-10-21T11:36:00", assignee: "L. Chen", citizen: CITIZENS[9], desc: DESCS["Damaged bin"][1] },
  { n: 11, cat: "Street litter hotspot", pri: "High", sector: 1, subsector: 1, at: "2026-10-23T16:20:00", assignee: "A. Rahman", citizen: CITIZENS[10], desc: DESCS["Street litter hotspot"][1], slaHours: 12 },
  { n: 12, cat: "Recycling contamination", pri: "Medium", sector: 3, subsector: 4, at: "2026-10-20T15:10:00", assignee: "J. Okafor", citizen: CITIZENS[11], desc: DESCS["Recycling contamination"][1] },
  { n: 13, cat: "Bin overflowing", pri: "Low", sector: 5, subsector: 5, at: "2026-10-20T17:44:00", assignee: null, citizen: CITIZENS[12], desc: DESCS["Bin overflowing"][2] },
  { n: 14, cat: "Illegal dumping", pri: "Medium", sector: 1, subsector: 2, at: "2026-10-20T19:02:00", assignee: "A. Rahman", citizen: CITIZENS[13], desc: DESCS["Illegal dumping"][2] },
  { n: 15, cat: "Missed collection", pri: "Low", sector: 7, subsector: 8, at: "2026-10-19T08:26:00", assignee: "L. Chen", citizen: CITIZENS[14], desc: DESCS["Missed collection"][2] },
  { n: 16, cat: "Damaged bin", pri: "High", sector: 5, subsector: 6, at: "2026-10-22T23:15:00", assignee: "L. Chen", citizen: CITIZENS[15], desc: DESCS["Damaged bin"][2], slaHours: 12 },
  { n: 17, cat: "Street litter hotspot", pri: "Medium", sector: 3, subsector: 3, at: "2026-10-19T10:52:00", assignee: null, citizen: CITIZENS[16], desc: DESCS["Street litter hotspot"][2] },
  { n: 18, cat: "Recycling contamination", pri: "Low", sector: 7, subsector: 9, at: "2026-10-18T13:18:00", assignee: "L. Chen", citizen: CITIZENS[17], desc: DESCS["Recycling contamination"][2] },
  { n: 19, cat: "Bin overflowing", pri: "Medium", sector: 1, subsector: 1, at: "2026-10-18T16:40:00", assignee: "A. Rahman", citizen: CITIZENS[18], desc: DESCS["Bin overflowing"][1] },
  { n: 20, cat: "Illegal dumping", pri: "Low", sector: 5, subsector: 5, at: "2026-10-17T09:05:00", assignee: null, citizen: CITIZENS[19], desc: DESCS["Illegal dumping"][0] },
  { n: 21, cat: "Street litter hotspot", pri: "High", sector: 7, subsector: 7, at: "2026-10-23T10:00:00", assignee: "L. Chen", citizen: CITIZENS[20], desc: DESCS["Street litter hotspot"][0], slaHours: 12 },
  { n: 22, cat: "Damaged bin", pri: "Medium", sector: 1, subsector: 4, at: "2026-10-17T12:33:00", assignee: null, citizen: CITIZENS[21], desc: DESCS["Damaged bin"][0] },
  { n: 23, cat: "Missed collection", pri: "Low", sector: 7, subsector: 8, at: "2026-10-17T15:47:00", assignee: "L. Chen", citizen: CITIZENS[22], desc: DESCS["Missed collection"][0] },
  { n: 24, cat: "Recycling contamination", pri: "Medium", sector: 5, subsector: 6, at: "2026-10-22T06:58:00", assignee: null, citizen: CITIZENS[23], desc: DESCS["Recycling contamination"][1] },
];

// §3b — 9 In review (High 3 · Medium 4 · Low 2, all assigned).
const IN_REVIEW_SEEDS: Seed[] = [
  { n: 25, cat: "Illegal dumping", pri: "High", sector: 3, subsector: 4, at: "2026-10-22T14:10:00", assignee: "J. Okafor", citizen: CITIZENS[3], desc: DESCS["Illegal dumping"][1], status: "In review", notes: ["Crew scheduled for Thu morning pickup."] },
  { n: 26, cat: "Bin overflowing", pri: "Medium", sector: 1, subsector: 1, at: "2026-10-22T11:20:00", assignee: "M. Alvarez", citizen: CITIZENS[5], desc: DESCS["Bin overflowing"][0], status: "In review" },
  { n: 27, cat: "Damaged bin", pri: "Low", sector: 5, subsector: 6, at: "2026-10-21T16:05:00", assignee: "L. Chen", citizen: CITIZENS[7], desc: DESCS["Damaged bin"][1], status: "In review" },
  { n: 28, cat: "Street litter hotspot", pri: "High", sector: 7, subsector: 9, at: "2026-10-21T09:48:00", assignee: "L. Chen", citizen: CITIZENS[9], desc: DESCS["Street litter hotspot"][2], status: "In review" },
  { n: 29, cat: "Missed collection", pri: "Medium", sector: 3, subsector: 3, at: "2026-10-20T08:36:00", assignee: "M. Alvarez", citizen: CITIZENS[11], desc: DESCS["Missed collection"][1], status: "In review" },
  { n: 30, cat: "Recycling contamination", pri: "Medium", sector: 5, subsector: 5, at: "2026-10-19T14:22:00", assignee: "L. Chen", citizen: CITIZENS[13], desc: DESCS["Recycling contamination"][0], status: "In review" },
  { n: 31, cat: "Bin overflowing", pri: "Low", sector: 1, subsector: 2, at: "2026-10-19T07:15:00", assignee: "M. Alvarez", citizen: CITIZENS[15], desc: DESCS["Bin overflowing"][2], status: "In review" },
  { n: 32, cat: "Illegal dumping", pri: "High", sector: 7, subsector: 8, at: "2026-10-18T19:40:00", assignee: "J. Okafor", citizen: CITIZENS[17], desc: DESCS["Illegal dumping"][2], status: "In review" },
  { n: 33, cat: "Damaged bin", pri: "Medium", sector: 3, subsector: 4, at: "2026-10-18T10:08:00", assignee: "J. Okafor", citizen: CITIZENS[19], desc: DESCS["Damaged bin"][2], status: "In review" },
];

function defaultSla(pri: ReportPriority): number {
  return pri === "High" ? 12 : 24;
}

// Sector anchor points around the township (Klang Valley-ish, ~3.0N 101.5E).
// Each sector sits ~0.03–0.05° from the others; sub-sectors within a sector fan out
// ~0.006°; individual reports jitter a few hundred metres so neighbours still
// group into the same map cluster. Deterministic (pure function of sector /
// subsector / report number) — no randomness, stable across reloads.
const SECTOR_ANCHORS: Record<number, { lat: number; lng: number }> = {
  1: { lat: 3.0752, lng: 101.5148 },
  3: { lat: 3.1031, lng: 101.5437 },
  5: { lat: 3.0462, lng: 101.5612 },
  7: { lat: 3.1288, lng: 101.4921 },
};

function gps(
  sector: number,
  subsector: number,
  n: number
): { lat: number; lng: number } {
  const anchor = SECTOR_ANCHORS[sector] ?? SECTOR_ANCHORS[1];
  const fan = (subsector % 3) - 1; // -1 / 0 / 1 — spreads sub-sectors in a sector
  const lat = anchor.lat + fan * 0.0058 + ((n * 17) % 7) * 0.0009;
  const lng = anchor.lng + fan * 0.0047 + ((n * 23) % 7) * 0.0011;
  return { lat: Number(lat.toFixed(4)), lng: Number(lng.toFixed(4)) };
}

function buildTimeline(status: ReportStatus, reportedAt: string): ReportEvent[] {
  const events: ReportEvent[] = [
    { status: "Received", at: reportedAt, by: "Citizen app" },
  ];
  if (status === "In review" || status === "In Progress" || status === "Resolved") {
    events.push({
      status: "Acknowledged",
      at: shiftHours(reportedAt, 1),
      by: "Duty desk",
    });
  }
  if (status === "In Progress" || status === "Resolved") {
    events.push({
      status: "In Progress",
      at: shiftHours(reportedAt, 3),
      by: "Response crew",
    });
  }
  if (status === "Resolved") {
    events.push({
      status: "Resolved",
      at: shiftHours(reportedAt, 8),
      by: "Response crew",
    });
  }
  return events;
}

function shiftHours(iso: string, hours: number): string {
  const d = new Date(iso);
  d.setTime(d.getTime() + hours * 3_600_000);
  // Pure naive-local round trip — `new Date(naive)` parses local, and local
  // getters format back, so no timezone shift (never toISOString()).
  const pad = (n: number) => String(n).padStart(2, "0");
  return (
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
    `T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
  );
}

function buildReport(seed: Seed): Report {
  const status: ReportStatus = seed.status ?? "Open";
  return {
    id: `RPT-${String(2400 + seed.n).padStart(4, "0")}`,
    category: seed.cat,
    priority: seed.pri,
    sector: seed.sector,
    subsector: seed.subsector,
    status,
    reportedAt: seed.at,
    assignee: seed.assignee,
    description: seed.desc,
    citizenName: seed.citizen,
    gps: gps(seed.sector, seed.subsector, seed.n),
    slaHours: seed.slaHours ?? defaultSla(seed.pri),
    slaStartedAt: seed.at,
    notes: seed.notes ?? [],
    timeline: buildTimeline(status, seed.at),
  };
}

/** 24 Open + 9 In review (33 rows); default table filter shows Open only. */
export const reports: Report[] = [...OPEN_SEEDS, ...IN_REVIEW_SEEDS].map(buildReport);

/** 61 lifetime resolved reports for the KPI aggregate (not in the main table). */
export const resolvedReportsSample: ResolvedSample[] = Array.from(
  { length: 61 },
  (_, i) => {
    const sector = SECTORS[i % SECTORS.length];
    const day = 12 + (i % 11); // 12..22 Oct
    return {
      id: `RPT-${String(2301 + i).padStart(4, "0")}`,
      sector,
      resolvedAt: `2026-10-${String(day).padStart(2, "0")}T${String(9 + (i % 8)).padStart(2, "0")}:${String((i * 7) % 60).padStart(2, "0")}:00`,
    };
  }
);

export const RESOLVED_LIFETIME_COUNT = 61;

// P2-SPEC §6 — KPI row numbers are static aggregates of the seeded dummy data
// (Open 24 / In review 9 / Resolved 61 / Avg 2.4h). Drawer actions mutate the
// table only; the KPI cards never drift.
export const OPEN_KPI_COUNT = reports.filter((r) => r.status === "Open").length; // 24
export const IN_REVIEW_KPI_COUNT = reports.filter((r) => r.status === "In review").length; // 9
