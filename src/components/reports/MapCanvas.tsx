"use client";

// Task A — real OSM map canvas (leaflet, no react-leaflet).
//
// Mirrors the Android counterpart (flutter_map + OpenStreetMap raster tiles):
// this component owns the leaflet instance and renders sector-filtered pins and
// simple client-side clusters as divIcon markers. It is imported ONLY via
// next/dynamic ssr:false from map-view.tsx, so leaflet never touches the
// server render and `pnpm build` stays static-safe.
//
// OSM tile URL (runtime-only network fetch — the one sanctioned remote asset;
// see README "Deviations from spec"):
//   https://tile.openstreetmap.org/{z}/{x}/{y}.png
// If tiles cannot load (offline demo), the container keeps its grey/grid
// background and pins, clusters, zoom and the drawer all stay interactive.
import * as React from "react";
import L from "leaflet";
import "leaflet/dist/leaflet.css";

import type { Report } from "@/lib/types";
import { mostRecent, type MapCanvasStats } from "./map-utils";

const OSM_TILE_URL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
const OSM_ATTRIBUTION =
  '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';

/** Township centre (mean of the sector anchors in lib/data/reports.ts). */
const TOWNSHIP_CENTER: L.LatLngExpression = [3.0883, 101.528];
const DEFAULT_ZOOM = 13;

/** Pixels within which two pins merge into a cluster at the current zoom. */
const CLUSTER_RADIUS_PX = 52;

const PRIORITY_CLASS: Record<Report["priority"], string> = {
  High: "map-pin--high",
  Medium: "map-pin--medium",
  Low: "map-pin--low",
};

interface Cluster {
  reports: Report[];
  center: L.LatLng;
  single: boolean;
}

/** Greedy screen-space clustering — no clustering library required. */
function clusterize(
  reports: Report[],
  map: L.Map,
  thresholdPx: number
): Cluster[] {
  const pts = reports.map((r) => ({
    report: r,
    xy: map.project([r.gps.lat, r.gps.lng], map.getZoom()),
  }));
  const used = new Array(pts.length).fill(false);
  const out: Cluster[] = [];
  for (let i = 0; i < pts.length; i += 1) {
    if (used[i]) continue;
    used[i] = true;
    const members: Report[] = [pts[i].report];
    for (let j = i + 1; j < pts.length; j += 1) {
      if (used[j]) continue;
      const dx = pts[i].xy.x - pts[j].xy.x;
      const dy = pts[i].xy.y - pts[j].xy.y;
      if (dx * dx + dy * dy <= thresholdPx * thresholdPx) {
        used[j] = true;
        members.push(pts[j].report);
      }
    }
    const lat =
      members.reduce((acc, r) => acc + r.gps.lat, 0) / members.length;
    const lng =
      members.reduce((acc, r) => acc + r.gps.lng, 0) / members.length;
    out.push({
      reports: members,
      center: L.latLng(lat, lng),
      single: members.length === 1,
    });
  }
  return out;
}

export interface MapCanvasProps {
  /** Sector-filtered Open + In review reports to draw. */
  reports: Report[];
  /** Currently selected report id (drives the mini card + pin ring). */
  selectedId: string | null;
  /** Called when a pin or a cluster is clicked (source distinguishes). */
  onSelect: (id: string, source: "pin" | "cluster") => void;
  /** Live cluster/pin counts for the subline ("6 pins · 2 clusters · …"). */
  onStats: (stats: MapCanvasStats) => void;
  /** Bump this key to re-fit the viewport (e.g. when the sector chip changes). */
  fitKey: string;
}

export default function MapCanvas({
  reports,
  selectedId,
  onSelect,
  onStats,
  fitKey,
}: MapCanvasProps) {
  const containerRef = React.useRef<HTMLDivElement | null>(null);
  const mapRef = React.useRef<L.Map | null>(null);
  const layerRef = React.useRef<L.LayerGroup | null>(null);
  // Latest values reachable from leaflet event handlers (registered once).
  const reportsRef = React.useRef(reports);
  const selectedRef = React.useRef(selectedId);
  const selectRef = React.useRef(onSelect);
  const statsRef = React.useRef(onStats);
  const fittedRef = React.useRef<string | null>(null);

  reportsRef.current = reports;
  selectedRef.current = selectedId;
  selectRef.current = onSelect;
  statsRef.current = onStats;

  // Draw (or redraw) markers for the current reports + selection + zoom.
  const redraw = React.useCallback(() => {
    const map = mapRef.current;
    const layer = layerRef.current;
    if (!map || !layer) return;

    layer.clearLayers();
    const list = reportsRef.current;
    if (list.length === 0) {
      statsRef.current({ pins: 0, clusters: 0 });
      return;
    }

    const clusters = clusterize(list, map, CLUSTER_RADIUS_PX);
    let pins = 0;
    let multi = 0;

    clusters.forEach((cluster) => {
      if (cluster.single) {
        pins += 1;
        const report = cluster.reports[0];
        const selected = report.id === selectedRef.current;
        const icon = L.divIcon({
          className: "",
          html: `<div class="map-pin ${PRIORITY_CLASS[report.priority]}${
            selected ? " map-pin--selected" : ""
          }" aria-hidden="true"></div>`,
          iconSize: [26, 26],
          iconAnchor: [13, 13],
        });
        const marker = L.marker(cluster.center, {
          icon,
          keyboard: true, // leaflet makes the marker focusable + Enter-clickable
          title: `${report.id} · ${report.category} · ${report.priority} priority`,
          riseOnHover: true,
        });
        marker.on("click", () => selectRef.current(report.id, "pin"));
        marker.addTo(layer);
      } else {
        multi += 1;
        const newest = mostRecent(cluster.reports);
        const selected =
          newest !== undefined && newest.id === selectedRef.current;
        const icon = L.divIcon({
          className: "",
          html: `<div class="map-cluster${
            selected ? " map-cluster--selected" : ""
          }" aria-hidden="true">${cluster.reports.length}</div>`,
          iconSize: undefined,
          iconAnchor: [17, 17],
        });
        const marker = L.marker(cluster.center, {
          icon,
          keyboard: true,
          title: `${cluster.reports.length} reports clustered — click to zoom and select the most recent`,
          riseOnHover: true,
        });
        marker.on("click", () => {
          // Zoom one level into the cluster and select its newest report.
          map.setView(cluster.center, Math.min(map.getZoom() + 1, 18), {
            animate: true,
          });
          if (newest) selectRef.current(newest.id, "cluster");
        });
        marker.addTo(layer);
      }
    });

    statsRef.current({ pins, clusters: multi });
  }, []);

  // Create the map once.
  React.useEffect(() => {
    if (!containerRef.current || mapRef.current) return;
    const map = L.map(containerRef.current, {
      center: TOWNSHIP_CENTER,
      zoom: DEFAULT_ZOOM,
      zoomControl: true,
      attributionControl: true,
      scrollWheelZoom: true,
    });
    L.tileLayer(OSM_TILE_URL, {
      maxZoom: 19,
      attribution: OSM_ATTRIBUTION,
    }).addTo(map);
    layerRef.current = L.layerGroup().addTo(map);
    map.on("zoomend", redraw);
    mapRef.current = map;
    redraw();
    return () => {
      map.remove();
      mapRef.current = null;
      layerRef.current = null;
      // F6 — drop the fit memo too so a StrictMode remount re-runs the
      // initial fitBounds (otherwise the second mount skips the first fit).
      fittedRef.current = null;
    };
  }, [redraw]);

  // Redraw when the data or selection changes.
  React.useEffect(() => {
    redraw();
  }, [reports, selectedId, redraw]);

  // Re-fit the viewport when the sector chip (fitKey) changes.
  React.useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    if (fittedRef.current === fitKey) return;
    fittedRef.current = fitKey;
    if (reports.length === 0) {
      map.setView(TOWNSHIP_CENTER, DEFAULT_ZOOM, { animate: false });
      return;
    }
    const bounds = L.latLngBounds(
      reports.map((r) => [r.gps.lat, r.gps.lng] as L.LatLngTuple)
    );
    map.fitBounds(bounds, { padding: [48, 48], maxZoom: 16, animate: false });
  }, [fitKey, reports]);

  // Leaflet measures its container after mount; react-size changes (mobile
  // drawer, sidebar toggle) need an explicit invalidateSize.
  React.useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    const id = window.setTimeout(() => map.invalidateSize(), 60);
    return () => window.clearTimeout(id);
  }, []);

  return (
    <div
      ref={containerRef}
      className="map-tile-bg map-grid absolute inset-0 h-full w-full"
      // The accessible surface is declared by the parent <section role="map">;
      // individual pins are reachable via leaflet keyboard markers and the
      // visually-hidden report list rendered next to the map.
    />
  );
}
