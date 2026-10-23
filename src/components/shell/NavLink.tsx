"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { cn } from "@/components/ui/utils";

interface NavLinkProps {
  href: string;
  label: string;
  icon: React.ReactNode;
  onNavigate?: () => void;
}

export function NavLink({ href, label, icon, onNavigate }: NavLinkProps) {
  const pathname = usePathname();
  const active =
    pathname === href ||
    (href !== "/reports-queue" &&
      href !== "/" &&
      pathname.startsWith(href));

  return (
    <Link
      href={href}
      onClick={onNavigate}
      aria-current={active ? "page" : undefined}
      className={cn(
        // ring-offset follows the sidebar surface token (F1): token-driven so
        // the focus halo matches the dark sidebar too — no light-only hex.
        "group flex min-h-[44px] items-center gap-3 rounded-[8px] px-3 py-2 text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--focus-ring)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--sidebar)]",
        active
          ? "border-b-[3px] border-b-[#2E7D32] text-[var(--green-text)]"
          : "text-ink-tertiary hover:bg-[var(--active-tint)] hover:text-[var(--green-text)]"
      )}
      title={label}
    >
      <span
        aria-hidden="true"
        className={cn(
          "flex h-5 w-5 shrink-0 items-center justify-center",
          active ? "text-[var(--green-text)]" : "text-ink-secondary group-hover:text-[var(--green-text)]"
        )}
      >
        {icon}
      </span>
      <span className="truncate lg:hidden xl:inline">{label}</span>
      {active ? (
        <span className="sr-only">(current page)</span>
      ) : null}
    </Link>
  );
}
