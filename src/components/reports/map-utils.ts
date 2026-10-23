// Task A — leaflet-free helpers shared by MapView (which must stay import-
// safe for the server bundle) and MapCanvas (which imports leaflet).
import type { Report } from "@/lib/types";

export interface MapCanvasStats {
  pins: number; // single-report pins drawn
  clusters: number; // multi-report clusters drawn
}

/** Most recently reported report (frozen October 2026 clock). */
export function mostRecent(list: Report[]): Report | undefined {
  return list.reduce<Report | undefined>(
    (acc, r) => (!acc || r.reportedAt > acc.reportedAt ? r : acc),
    undefined
  );
}
