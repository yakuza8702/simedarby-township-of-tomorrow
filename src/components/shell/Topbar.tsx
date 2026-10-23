"use client";

import { usePathname, useRouter } from "next/navigation";
import * as React from "react";
import { ChevronDown, History, LogOut, Megaphone, Menu } from "lucide-react";

import { useStore } from "@/lib/store";
import { clearSession } from "@/lib/session";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Sheet,
  SheetContent,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { Sidebar } from "./Sidebar";
import { ThemeToggle } from "./ThemeToggle";

const TITLES: Array<[string, string]> = [
  ["/reports-queue", "Reports queue"],
  ["/sectors", "Sectors"],
  ["/collection-routes", "Collection Routes"],
  ["/users", "Users"],
  ["/broadcast", "Broadcast"],
  ["/audit-log", "Audit log"],
  ["/settings", "Settings"],
];

export function Topbar() {
  const pathname = usePathname();
  const router = useRouter();
  const { currentUser } = useStore();
  const [open, setOpen] = React.useState(false);

  const title =
    TITLES.find(([prefix]) => pathname.startsWith(prefix))?.[1] ??
    "Council operations";

  const effectiveViewer = currentUser.role === "Viewer";

  return (
    <header className="sticky top-0 z-40 flex h-[56px] shrink-0 items-center gap-3 border-b border-[var(--border-plain)] bg-[var(--surface)] px-4 lg:px-6">
      <Sheet open={open} onOpenChange={setOpen}>
        <SheetTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            className="lg:hidden"
            aria-label="Open navigation menu"
          >
            <Menu className="h-5 w-5" />
          </Button>
        </SheetTrigger>
        <SheetContent side="left" className="w-[260px] p-0 sm:max-w-[260px]">
          <SheetTitle className="sr-only">Navigation</SheetTitle>
          <Sidebar onNavigate={() => setOpen(false)} />
        </SheetContent>
      </Sheet>

      <div className="min-w-0 flex-1">
        <h1 className="truncate text-base font-semibold text-ink-primary">
          {title}
        </h1>
      </div>

      <div className="hidden items-center gap-2 rounded-full border border-[var(--border-plain)] bg-[var(--input-bg)] px-3 py-1 text-xs text-ink-secondary md:flex">
        <span
          aria-hidden="true"
          className="h-2 w-2 rounded-full bg-[#388E3C]"
        />
        Offline demo · dummy data
      </div>

      {/* Task C — light/dark toggle (persisted; no-flash boot script in root layout). */}
      <ThemeToggle />

      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            variant="ghost"
            className="gap-2 rounded-full pl-1 pr-2 hover:bg-[var(--active-tint)]"
            aria-label={`Account menu for ${currentUser.fullName}`}
          >
            <Avatar className="h-7 w-7">
              <AvatarFallback>{currentUser.initials}</AvatarFallback>
            </Avatar>
            <span className="hidden max-w-[140px] truncate text-sm text-ink-primary sm:inline">
              {currentUser.fullName}
              {effectiveViewer ? " · Viewer" : ""}
            </span>
            <ChevronDown className="hidden h-4 w-4 text-ink-secondary sm:block" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-56">
          <DropdownMenuLabel>
            <span className="block truncate">{currentUser.fullName}</span>
            <span className="block truncate text-xs font-normal text-ink-secondary">
              {currentUser.email}
            </span>
            <span className="block truncate text-xs font-normal text-ink-secondary">
              {currentUser.role}
            </span>
          </DropdownMenuLabel>
          <DropdownMenuSeparator />
          {/* Removed from the sidebar (Penpot lists six items); kept reachable here. */}
          <DropdownMenuItem onSelect={() => router.push("/broadcast")}>
            <Megaphone className="mr-2 h-4 w-4" />
            Broadcast
          </DropdownMenuItem>
          <DropdownMenuItem onSelect={() => router.push("/audit-log")}>
            <History className="mr-2 h-4 w-4" />
            Audit log
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            onSelect={() => {
              clearSession();
              router.push("/login");
              router.refresh();
            }}
            className="text-[var(--chip-red-text)] focus:text-[var(--chip-red-text)]"
          >
            <LogOut className="mr-2 h-4 w-4" />
            Sign out
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </header>
  );
}
