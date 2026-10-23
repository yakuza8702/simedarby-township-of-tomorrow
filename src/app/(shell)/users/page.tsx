"use client";

// Task B — /users: council staff accounts, roles and access review.
// Replaces the "coming online next" placeholder card.
//
// Reuses the RolesTable roster (same 5 members Settings → Roles edits) with
// avatar initials, role, scope, last-active and per-resource permission
// chips. The access-review panel summarises the role counts (Admin 1 /
// Agent+ 1 / Agent 2 / Viewer 1). Clicking a row opens a read-only access
// preview in the same modal pattern as PermissionModal (viewer preview).
import * as React from "react";

import { ShieldCheck } from "lucide-react";

import {
  CONSOLE_RESOURCES,
  USER_ACTIVITY,
  deriveUserTotals,
  memberResourcePermission,
  permissionChipClass,
} from "@/lib/data/users";
import { formatClock } from "@/lib/mock-delay";
import { useStore } from "@/lib/store";
import type { RoleMember } from "@/lib/types";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { cn } from "@/components/ui/utils";

function scopeLabel(member: RoleMember): string {
  return typeof member.scope === "string"
    ? member.scope
    : `Sector ${member.scope.from}–${member.scope.to}`;
}

/** Role chip palette — Admin green, Agent+ blue, Agent plain, Viewer amber. */
function roleChipClass(role: RoleMember["role"]): string {
  if (role === "Admin")
    return "bg-[var(--chip-green-bg)] text-[var(--green-text)]";
  if (role === "Agent+")
    return "bg-[var(--chip-blue-bg)] text-[var(--chip-blue-text)]";
  if (role === "Agent")
    return "border border-[var(--border-plain)] bg-[var(--input-bg)] text-ink-primary";
  return "bg-[var(--chip-amber-bg)] text-[var(--chip-amber-text)]";
}

export default function UsersPage() {
  const store = useStore();
  const [selected, setSelected] = React.useState<RoleMember | null>(null);

  // Live roster — Settings → Roles edits land here (shared store).
  const members = store.roleMembers;
  const activityFor = (id: string) => USER_ACTIVITY.find((a) => a.userId === id);
  // F4 — hero counts derive from the live roster (recompute after role edits).
  const totals = deriveUserTotals(members);

  return (
    <div className="space-y-6 pb-10">
      <div>
        <h2 className="text-xl font-bold text-ink-primary">Users</h2>
        <p className="text-sm text-ink-secondary">
          {totals.staff} council staff · {totals.admins} admin ·{" "}
          {totals.activeToday} active today · updated 5 min ago
        </p>
      </div>

      {/* Access review panel — role counts with badges */}
      <section aria-label="Access review" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="text-sm font-semibold text-ink-primary">
            Access review
          </h3>
          <p className="text-xs text-ink-secondary">
            Role distribution across the console — review quarterly.
          </p>
        </div>
        <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {(
            [
              ["Admin", "Full access"],
              ["Agent+", "Edit+Assign+SLA"],
              ["Agent", "Edit+Assign"],
              ["Viewer", "Read-only View"],
            ] as const
          ).map(([role, permission]) => {
            const count = members.filter((m) => m.role === role).length;
            return (
              <li
                key={role}
                className="rounded-[12px] border border-[var(--border-plain)] bg-[var(--surface)] p-4"
              >
                <div className="flex items-center justify-between gap-2">
                  <span
                    className={cn(
                      "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-semibold",
                      roleChipClass(role)
                    )}
                  >
                    <ShieldCheck className="h-3.5 w-3.5" aria-hidden="true" />
                    {role}
                  </span>
                  <Badge className="rounded-full bg-[var(--input-bg)] text-ink-primary">
                    {count}
                  </Badge>
                </div>
                <p className="mt-2 text-xs text-ink-secondary">{permission}</p>
                <p className="mt-1 truncate text-xs text-ink-secondary">
                  {members
                    .filter((m) => m.role === role)
                    .map((m) => m.fullName)
                    .join(", ") || "—"}
                </p>
              </li>
            );
          })}
        </ul>
      </section>

      {/* Staff table — avatar / role / scope / last active / permissions */}
      <section aria-label="Council staff accounts" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="text-sm font-semibold text-ink-primary">
            Council staff
          </h3>
          <p className="text-xs text-ink-secondary">
            Select a row to preview the account&apos;s access.
          </p>
        </div>

        <div className="panel-scroll overflow-x-auto rounded-[12px] border border-[var(--border-plain)] bg-[var(--surface)]">
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead scope="col">User</TableHead>
                <TableHead scope="col">Role</TableHead>
                <TableHead scope="col">Scope</TableHead>
                <TableHead scope="col" className="hidden md:table-cell">
                  Last active
                </TableHead>
                <TableHead scope="col">Per-resource permissions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {members.map((member) => {
                const activity = activityFor(member.id);
                return (
                  <TableRow
                    key={member.id}
                    tabIndex={0}
                    role="button"
                    aria-label={`Preview access for ${member.fullName}, ${member.role}`}
                    onClick={() => setSelected(member)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" || e.key === " ") {
                        e.preventDefault();
                        setSelected(member);
                      }
                    }}
                    className={cn(
                      "cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--focus-ring)]",
                      selected?.id === member.id && "bg-[var(--sidebar)]"
                    )}
                  >
                    <TableCell>
                      <div className="flex items-center gap-3">
                        <Avatar>
                          <AvatarFallback>{member.initials}</AvatarFallback>
                        </Avatar>
                        <div className="min-w-0">
                          <p className="font-semibold text-ink-primary">
                            {member.fullName}
                          </p>
                          <p className="truncate text-xs text-ink-secondary">
                            {member.email}
                          </p>
                        </div>
                      </div>
                    </TableCell>
                    <TableCell>
                      <span
                        className={cn(
                          "inline-flex rounded-full px-2.5 py-0.5 text-xs font-semibold",
                          roleChipClass(member.role)
                        )}
                      >
                        {member.role}
                      </span>
                    </TableCell>
                    <TableCell className="whitespace-nowrap">
                      {scopeLabel(member)}
                    </TableCell>
                    <TableCell className="hidden whitespace-nowrap text-xs text-ink-secondary md:table-cell">
                      {activity ? (
                        <>
                          {formatClock(activity.lastActiveAt)} ·{" "}
                          {activity.lastActiveAt.slice(0, 10)}
                          <span className="block truncate">
                            {activity.lastAction}
                          </span>
                        </>
                      ) : (
                        "—"
                      )}
                    </TableCell>
                    <TableCell>
                      <div className="flex flex-wrap gap-1">
                        {CONSOLE_RESOURCES.slice(0, 3).map((resource) => (
                          <span
                            key={resource}
                            className={cn(
                              "inline-flex whitespace-nowrap rounded-full border px-2 py-0.5 text-[11px] font-medium",
                              permissionChipClass(
                                memberResourcePermission(member, resource)
                              )
                            )}
                          >
                            {resource}:{" "}
                            {memberResourcePermission(member, resource)}
                          </span>
                        ))}
                        <span className="text-[11px] text-ink-secondary">
                          +{CONSOLE_RESOURCES.length - 3} more
                        </span>
                      </div>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </div>
      </section>

      {/* Access preview modal — same pattern as PermissionModal (read-only). */}
      <Dialog
        open={Boolean(selected)}
        onOpenChange={(open) => {
          if (!open) setSelected(null);
        }}
      >
        <DialogContent
          aria-describedby="user-access-desc"
          className="max-w-[520px]"
        >
          {selected ? (
            <>
              <DialogHeader>
                <DialogTitle className="flex items-center gap-2">
                  <Avatar className="h-7 w-7">
                    <AvatarFallback>{selected.initials}</AvatarFallback>
                  </Avatar>
                  {selected.fullName} · {selected.role}
                </DialogTitle>
                <DialogDescription id="user-access-desc">
                  Read-only access preview — role changes happen in Settings →
                  Roles.
                </DialogDescription>
              </DialogHeader>

              <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
                <dt className="text-ink-secondary">Email</dt>
                <dd className="truncate font-medium">{selected.email}</dd>
                <dt className="text-ink-secondary">Scope</dt>
                <dd className="font-medium">{scopeLabel(selected)}</dd>
                <dt className="text-ink-secondary">Permissions</dt>
                <dd className="font-medium">{selected.permissions}</dd>
                <dt className="text-ink-secondary">Last active</dt>
                <dd className="font-medium">
                  {activityFor(selected.id)?.lastActiveAt.replace("T", " ") ??
                    "—"}
                </dd>
              </dl>

              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-ink-secondary">
                  Per-resource permissions
                </p>
                <ul className="mt-2 flex flex-wrap gap-1.5">
                  {CONSOLE_RESOURCES.map((resource) => (
                    <li key={resource}>
                      <span
                        className={cn(
                          "inline-flex whitespace-nowrap rounded-full border px-2 py-0.5 text-[11px] font-medium",
                          permissionChipClass(
                            memberResourcePermission(selected, resource)
                          )
                        )}
                      >
                        {resource}:{" "}
                        {memberResourcePermission(selected, resource)}
                      </span>
                    </li>
                  ))}
                </ul>
              </div>

              <DialogFooter>
                <Button onClick={() => setSelected(null)}>Back to users</Button>
              </DialogFooter>
            </>
          ) : null}
        </DialogContent>
      </Dialog>
    </div>
  );
}
