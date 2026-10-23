// Task B — /sectors dummy data: 7 sectors, weekly collection calendars and
// crew rosters. Sector 1/3/5/7 carry the report sub-sectors (P2-SPEC §3); sectors
// 2/4/6 are INFERRED filler so the console presents a full 7-sector township.
//
// All numbers are static INFERRED dummy figures (October 2026 programme) —
// no backend, no sync, consistent with the rest of the console.

import type { ReportCategory } from "../types";

export type WasteStream =
  | "General waste"
  | "Organic"
  | "Recycling"
  | "Bulky items";

/** Stream dot class (globals.css maps stream-dot--* with dark variants). */
export const STREAM_DOT: Record<WasteStream, string> = {
  "General waste": "stream-dot--general",
  Organic: "stream-dot--organic",
  Recycling: "stream-dot--recycling",
  "Bulky items": "stream-dot--glass",
};

export interface SectorCard {
  sector: number;
  subsectors: number[];
  areaKm2: number;
  households: number;
  residents: number;
  /** Sub-sector ids with the heaviest report load (drives the map highlight). */
  hotSubsectors: number[];
  lead: string;
}

/** 7 sectors; 1/3/5/7 align with the report dataset (sub-sectors 1..9). */
export const SECTOR_CARDS: SectorCard[] = [
  {
    sector: 1,
    subsectors: [1, 2],
    areaKm2: 4.8,
    households: 3120,
    residents: 9480,
    hotSubsectors: [1],
    lead: "M. Alvarez",
  },
  {
    sector: 2,
    subsectors: [10],
    areaKm2: 3.1,
    households: 1740,
    residents: 5210,
    hotSubsectors: [10],
    lead: "R. Krishnan",
  },
  {
    sector: 3,
    subsectors: [3, 4],
    areaKm2: 5.6,
    households: 3480,
    residents: 10620,
    hotSubsectors: [3, 4],
    lead: "J. Okafor",
  },
  {
    sector: 4,
    subsectors: [11],
    areaKm2: 2.7,
    households: 1520,
    residents: 4540,
    hotSubsectors: [11],
    lead: "S. Devi",
  },
  {
    sector: 5,
    subsectors: [5, 6],
    areaKm2: 6.2,
    households: 2960,
    residents: 8870,
    hotSubsectors: [6],
    lead: "L. Chen",
  },
  {
    sector: 6,
    subsectors: [12],
    areaKm2: 3.9,
    households: 1880,
    residents: 5660,
    hotSubsectors: [12],
    lead: "T. Nguyen",
  },
  {
    sector: 7,
    subsectors: [7, 8, 9],
    areaKm2: 7.4,
    households: 3240,
    residents: 9930,
    hotSubsectors: [8],
    lead: "L. Chen",
  },
];

export const SECTOR_TOTALS = {
  sectors: SECTOR_CARDS.length,
  subsectors: SECTOR_CARDS.reduce((n, w) => n + w.subsectors.length, 0),
  households: SECTOR_CARDS.reduce((n, w) => n + w.households, 0),
  residents: SECTOR_CARDS.reduce((n, w) => n + w.residents, 0),
};

// ---- Weekly collection calendar (per sector, Mon–Sun) ----------------------

export const WEEK_DAYS = [
  "Mon",
  "Tue",
  "Wed",
  "Thu",
  "Fri",
  "Sat",
  "Sun",
] as const;

/** sector → day → streams collected that day (INFERRED rota). */
export const COLLECTION_CALENDAR: Record<number, Partial<Record<string, WasteStream[]>>> = {
  1: {
    Mon: ["General waste", "Recycling"],
    Wed: ["General waste", "Organic"],
    Fri: ["General waste", "Recycling"],
    Sat: ["Organic"],
  },
  2: {
    Tue: ["General waste"],
    Thu: ["General waste", "Recycling"],
    Sat: ["Organic"],
  },
  3: {
    Mon: ["General waste", "Organic"],
    Wed: ["General waste", "Recycling"],
    Fri: ["General waste", "Organic"],
    Sun: ["Bulky items"],
  },
  4: {
    Tue: ["General waste", "Recycling"],
    Thu: ["General waste"],
    Sat: ["General waste", "Organic"],
  },
  5: {
    Mon: ["General waste", "Recycling"],
    Wed: ["Organic"],
    Fri: ["General waste", "Recycling"],
    Sat: ["Bulky items"],
  },
  6: {
    Tue: ["General waste", "Organic"],
    Thu: ["General waste", "Recycling"],
    Sat: ["General waste"],
  },
  7: {
    Mon: ["General waste", "Organic"],
    Wed: ["General waste", "Recycling"],
    Fri: ["General waste", "Organic"],
    Sat: ["Recycling"],
    Sun: ["Bulky items"],
  },
};

// ---- Crew rosters ---------------------------------------------------------

export type CrewShift = "Morning 06:00–14:00" | "Afternoon 14:00–22:00" | "Night 22:00–06:00";

export interface Crew {
  id: string;
  name: string;
  sector: number;
  shift: CrewShift;
  lead: string;
  members: number;
  streams: WasteStream[];
  truck: string;
}

/** 8 crews across the 7 sectors; names reuse the role roster (§3c). */
export const CREWS: Crew[] = [
  {
    id: "CR-01",
    name: "Sector 1 Alpha",
    sector: 1,
    shift: "Morning 06:00–14:00",
    lead: "A. Rahman",
    members: 4,
    streams: ["General waste", "Recycling"],
    truck: "TG-041",
  },
  {
    id: "CR-02",
    name: "Sector 1 Bravo",
    sector: 1,
    shift: "Afternoon 14:00–22:00",
    lead: "M. Alvarez",
    members: 3,
    streams: ["Organic"],
    truck: "TG-018",
  },
  {
    id: "CR-03",
    name: "Sector 3 Alpha",
    sector: 3,
    shift: "Morning 06:00–14:00",
    lead: "J. Okafor",
    members: 4,
    streams: ["General waste", "Recycling"],
    truck: "TG-027",
  },
  {
    id: "CR-04",
    name: "Sector 3 Bravo",
    sector: 3,
    shift: "Night 22:00–06:00",
    lead: "P. Ndiaye",
    members: 3,
    streams: ["Bulky items"],
    truck: "TG-052",
  },
  {
    id: "CR-05",
    name: "Sector 5 Alpha",
    sector: 5,
    shift: "Morning 06:00–14:00",
    lead: "L. Chen",
    members: 4,
    streams: ["General waste", "Organic"],
    truck: "TG-033",
  },
  {
    id: "CR-06",
    name: "Sector 5 Bravo",
    sector: 5,
    shift: "Afternoon 14:00–22:00",
    lead: "S. Devi",
    members: 3,
    streams: ["Recycling"],
    truck: "TG-060",
  },
  {
    id: "CR-07",
    name: "Sector 7 Alpha",
    sector: 7,
    shift: "Morning 06:00–14:00",
    lead: "L. Chen",
    members: 5,
    streams: ["General waste", "Recycling", "Organic"],
    truck: "TG-014",
  },
  {
    id: "CR-08",
    name: "Sector 7 Bravo",
    sector: 7,
    shift: "Night 22:00–06:00",
    lead: "T. Nguyen",
    members: 3,
    streams: ["Bulky items"],
    truck: "TG-046",
  },
];

/** Total collections scheduled this week (sum of all day/stream entries). */
export const WEEKLY_COLLECTION_SLOTS = Object.values(COLLECTION_CALENDAR).reduce(
  (n, days) => n + Object.values(days).reduce((m, s) => m + (s?.length ?? 0), 0),
  0
);

/** Category → stream mapping used to tie reports to collection work. */
export const CATEGORY_STREAM: Partial<Record<ReportCategory, WasteStream>> = {
  "Bin overflowing": "General waste",
  "Illegal dumping": "Bulky items",
  "Missed collection": "General waste",
  "Damaged bin": "General waste",
  "Recycling contamination": "Recycling",
  "Street litter hotspot": "Organic",
};
