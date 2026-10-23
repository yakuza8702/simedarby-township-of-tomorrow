// Task B — /collection-routes dummy data: RT-1..RT-6 routes with truck,
// crew, sectors covered, ordered stop lists (RPT ids from the report dataset)
// and pickup progress. Truck ids follow the TG-0## style from the design
// notes; crews/leads reuse the roster names (§3c / lib/data/sectors.ts).
//
// Stops are plain RPT ids so the page can hydrate category/status from the
// live store (a stop always points at a real dummy report).

export type RouteStatus = "On schedule" | "Delayed";

export interface RouteStop {
  reportId: string;
  /** Planned arrival, "HH:MM" on the frozen October 2026 day. */
  eta: string;
}

export interface CollectionRoute {
  id: string; // RT-1..RT-6
  truck: string; // TG-041 style
  crew: string;
  lead: string;
  sectors: number[];
  stream: "General waste" | "Organic" | "Recycling" | "Bulky items";
  stops: RouteStop[];
  /** Stops already collected (progress = done / stops). */
  done: number;
  status: RouteStatus;
  /** Reason shown when Delayed (null when on schedule). */
  delayNote: string | null;
}

/** 6 routes for today's round (design: "6 routes today"). */
export const ROUTES: CollectionRoute[] = [
  {
    id: "RT-1",
    truck: "TG-041",
    crew: "Sector 1 Alpha",
    lead: "A. Rahman",
    sectors: [1],
    stream: "General waste",
    stops: [
      { reportId: "RPT-2404", eta: "06:20" },
      { reportId: "RPT-2419", eta: "06:55" },
      { reportId: "RPT-2402", eta: "07:30" },
      { reportId: "RPT-2414", eta: "08:05" },
      { reportId: "RPT-2422", eta: "08:40" },
      { reportId: "RPT-2411", eta: "09:15" },
      { reportId: "RPT-2426", eta: "09:50" },
      { reportId: "RPT-2431", eta: "10:25" },
    ],
    done: 5,
    status: "On schedule",
    delayNote: null,
  },
  {
    id: "RT-2",
    truck: "TG-027",
    crew: "Sector 3 Alpha",
    lead: "J. Okafor",
    sectors: [3],
    stream: "Recycling",
    stops: [
      { reportId: "RPT-2401", eta: "06:30" },
      { reportId: "RPT-2408", eta: "07:05" },
      { reportId: "RPT-2417", eta: "07:40" },
      { reportId: "RPT-2403", eta: "08:15" },
      { reportId: "RPT-2412", eta: "08:50" },
      { reportId: "RPT-2405", eta: "09:25" },
      { reportId: "RPT-2429", eta: "10:00" },
    ],
    done: 3,
    status: "Delayed",
    delayNote: "TG-027 hydraulic lift fault — swap to TG-052 after stop 4.",
  },
  {
    id: "RT-3",
    truck: "TG-033",
    crew: "Sector 5 Alpha",
    lead: "L. Chen",
    sectors: [5],
    stream: "Organic",
    stops: [
      { reportId: "RPT-2406", eta: "06:15" },
      { reportId: "RPT-2409", eta: "06:50" },
      { reportId: "RPT-2413", eta: "07:25" },
      { reportId: "RPT-2416", eta: "08:00" },
      { reportId: "RPT-2420", eta: "08:35" },
      { reportId: "RPT-2424", eta: "09:10" },
      { reportId: "RPT-2427", eta: "09:45" },
      { reportId: "RPT-2430", eta: "10:20" },
    ],
    done: 8,
    status: "On schedule",
    delayNote: null,
  },
  {
    id: "RT-4",
    truck: "TG-014",
    crew: "Sector 7 Alpha",
    lead: "L. Chen",
    sectors: [7],
    stream: "General waste",
    stops: [
      { reportId: "RPT-2410", eta: "06:40" },
      { reportId: "RPT-2415", eta: "07:15" },
      { reportId: "RPT-2418", eta: "07:50" },
      { reportId: "RPT-2421", eta: "08:25" },
      { reportId: "RPT-2423", eta: "09:00" },
      { reportId: "RPT-2428", eta: "09:35" },
      { reportId: "RPT-2432", eta: "10:10" },
    ],
    done: 2,
    status: "Delayed",
    delayNote: "Flooding on Jalan Melur — rerouted via sub-sector 9.",
  },
  {
    id: "RT-5",
    truck: "TG-052",
    crew: "Sector 3 Bravo",
    lead: "P. Ndiaye",
    sectors: [3, 7],
    stream: "Bulky items",
    stops: [
      { reportId: "RPT-2425", eta: "22:30" },
      { reportId: "RPT-2433", eta: "23:10" },
      { reportId: "RPT-2407", eta: "23:50" },
      { reportId: "RPT-2432", eta: "00:30" },
    ],
    done: 0,
    status: "On schedule",
    delayNote: null,
  },
  {
    id: "RT-6",
    truck: "TG-018",
    crew: "Sector 1 Bravo",
    lead: "M. Alvarez",
    sectors: [1, 5],
    stream: "Recycling",
    stops: [
      { reportId: "RPT-2426", eta: "14:30" },
      { reportId: "RPT-2431", eta: "15:05" },
      { reportId: "RPT-2406", eta: "15:40" },
      { reportId: "RPT-2424", eta: "16:15" },
      { reportId: "RPT-2413", eta: "16:50" },
      { reportId: "RPT-2420", eta: "17:25" },
    ],
    done: 1,
    status: "On schedule",
    delayNote: null,
  },
];

export const ROUTE_TOTALS = {
  routes: ROUTES.length,
  trucks: new Set(ROUTES.map((r) => r.truck)).size,
  stops: ROUTES.reduce((n, r) => n + r.stops.length, 0),
  delayed: ROUTES.filter((r) => r.status === "Delayed").length,
};

/** Crews available for reassignment (Assign button cycles through these). */
export const ASSIGNABLE_CREWS: Array<{ crew: string; lead: string; truck: string }> = [
  { crew: "Sector 1 Alpha", lead: "A. Rahman", truck: "TG-041" },
  { crew: "Sector 3 Alpha", lead: "J. Okafor", truck: "TG-027" },
  { crew: "Sector 5 Alpha", lead: "L. Chen", truck: "TG-033" },
  { crew: "Sector 7 Alpha", lead: "L. Chen", truck: "TG-014" },
  { crew: "Sector 3 Bravo", lead: "P. Ndiaye", truck: "TG-052" },
  { crew: "Sector 1 Bravo", lead: "M. Alvarez", truck: "TG-018" },
];
