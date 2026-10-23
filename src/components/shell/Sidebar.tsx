"use client";

import {
  ClipboardList,
  LayoutDashboard,
  Leaf,
  Map,
  Settings,
  Truck,
  Users,
} from "lucide-react";

import { NavLink } from "./NavLink";

// V2 — Penpot sidebar: exactly these six items, in this order.
// Audit log / Broadcast moved to the topbar avatar dropdown.
const NAV_ITEMS = [
  { href: "/", label: "Dashboard", icon: <LayoutDashboard className="h-5 w-5" /> },
  { href: "/reports-queue", label: "Reports Queue", icon: <ClipboardList className="h-5 w-5" /> },
  { href: "/sectors", label: "Sectors", icon: <Map className="h-5 w-5" /> },
  { href: "/collection-routes", label: "Collection Routes", icon: <Truck className="h-5 w-5" /> },
  { href: "/users", label: "Users", icon: <Users className="h-5 w-5" /> },
  { href: "/settings/roles", label: "Settings", icon: <Settings className="h-5 w-5" /> },
];

interface SidebarProps {
  /** Called after a nav link is clicked (closes the mobile drawer). */
  onNavigate?: () => void;
}

export function Sidebar({ onNavigate }: SidebarProps) {
  return (
    <nav
      aria-label="Primary"
      className="flex h-full w-full flex-col bg-[var(--sidebar)] px-3 py-4"
    >
      <div className="mb-6 flex items-center gap-2 px-2">
        <span
          aria-hidden="true"
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[#2E7D32] text-white"
        >
          <Leaf className="h-4 w-4" />
        </span>
        <span className="min-w-0 lg:hidden xl:block">
          <span className="block truncate text-sm font-bold text-ink-primary">
            Township of Tomorrow
          </span>
          <span className="block truncate text-xs text-ink-secondary">
            Council operations console
          </span>
        </span>
      </div>

      <ul className="flex flex-col gap-1">
        {NAV_ITEMS.map((item) => (
          <li key={item.href}>
            <NavLink {...item} onNavigate={onNavigate} />
          </li>
        ))}
      </ul>

      <div className="mt-auto px-2 pt-6 lg:hidden xl:block">
        <div className="rounded-[12px] border border-[var(--border-green)] bg-[var(--surface-70)] p-3">
          <p className="text-xs font-semibold text-ink-primary">
            Green community programme
          </p>
          <p className="mt-1 text-xs text-ink-secondary">
            Waste, reports and collection — one console.
          </p>
        </div>
        <p className="mt-3 text-[11px] text-ink-secondary">
          v0.3 · October 2026 · Offline demo data
        </p>
      </div>
    </nav>
  );
}
