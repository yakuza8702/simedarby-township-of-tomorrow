"use client";

// P2-SPEC §6 — roles table with inline row editing; saves hit the in-memory
// dummy-data copy and append an audit entry.
import { Check, Pencil, X } from "lucide-react";
import * as React from "react";

import { useStore } from "@/lib/store";
import type { Permission, RoleName, ScopeType } from "@/lib/types";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useToast } from "@/components/ui/use-toast";

const ROLE_OPTIONS: RoleName[] = ["Admin", "Agent", "Agent+", "Viewer"];
const PERMISSION_OPTIONS: Permission[] = [
  "Full access",
  "Edit+Assign",
  "Edit+Assign+SLA",
  "Read-only View",
];

function scopeLabel(scope: ScopeType): string {
  if (typeof scope === "string") return scope;
  return `Sector ${scope.from}–${scope.to}`;
}

interface Draft {
  role: RoleName;
  scopeMode: "All sectors" | "Read-only" | "range";
  from: number;
  to: number;
  permissions: Permission;
}

export function RolesTable() {
  const store = useStore();
  const { toast } = useToast();
  const [editingId, setEditingId] = React.useState<string | null>(null);
  const [draft, setDraft] = React.useState<Draft | null>(null);

  const startEdit = (id: string) => {
    const member = store.roleMembers.find((m) => m.id === id);
    if (!member) return;
    const scope = member.scope;
    setDraft({
      role: member.role,
      scopeMode:
        typeof scope === "string"
          ? scope === "All sectors"
            ? "All sectors"
            : "Read-only"
          : "range",
      from: typeof scope === "string" ? 1 : scope.from,
      to: typeof scope === "string" ? 7 : scope.to,
      permissions: member.permissions,
    });
    setEditingId(id);
  };

  const cancelEdit = () => {
    setEditingId(null);
    setDraft(null);
  };

  const saveEdit = (id: string) => {
    if (!draft) return;
    const scope: ScopeType =
      draft.scopeMode === "range"
        ? { from: Math.min(draft.from, draft.to), to: Math.max(draft.from, draft.to) }
        : draft.scopeMode;
    store.updateRoleMember(id, {
      role: draft.role,
      scope,
      permissions: draft.permissions,
    });
    toast({
      title: "Role updated",
      description: "Change written to the in-memory roster and audit log.",
      variant: "success",
    });
    cancelEdit();
  };

  return (
    <div className="overflow-hidden rounded-[12px] border border-[var(--border-plain)] bg-[var(--surface)]">
      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <TableHead scope="col">User</TableHead>
            <TableHead scope="col">Role</TableHead>
            <TableHead scope="col">Scope</TableHead>
            <TableHead scope="col">Per-resource permissions</TableHead>
            <TableHead scope="col">
              <span className="sr-only">Actions</span>
            </TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {store.roleMembers.map((member) => {
            const editing = editingId === member.id && draft;
            return (
              <TableRow key={member.id} className="hover:bg-transparent">
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
                  {editing ? (
                    <Select
                      value={draft.role}
                      onValueChange={(v) =>
                        setDraft({ ...draft, role: v as RoleName })
                      }
                    >
                      <SelectTrigger
                        className="h-9 w-32"
                        aria-label={`Role for ${member.fullName}`}
                      >
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {ROLE_OPTIONS.map((role) => (
                          <SelectItem key={role} value={role}>
                            {role}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  ) : (
                    <span className="font-medium">{member.role}</span>
                  )}
                </TableCell>
                <TableCell>
                  {editing ? (
                    <div className="flex flex-col gap-1.5">
                      <Select
                        value={draft.scopeMode}
                        onValueChange={(v) =>
                          setDraft({
                            ...draft,
                            scopeMode: v as Draft["scopeMode"],
                          })
                        }
                      >
                        <SelectTrigger
                          className="h-9 w-36"
                          aria-label={`Scope mode for ${member.fullName}`}
                        >
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="All sectors">All sectors</SelectItem>
                          <SelectItem value="range">Sector range…</SelectItem>
                          <SelectItem value="Read-only">Read-only</SelectItem>
                        </SelectContent>
                      </Select>
                      {draft.scopeMode === "range" ? (
                        <div className="flex items-center gap-1">
                          <label className="sr-only" htmlFor={`${member.id}-from`}>
                            Sector from
                          </label>
                          <input
                            id={`${member.id}-from`}
                            type="number"
                            min={1}
                            max={7}
                            value={draft.from}
                            onChange={(e) =>
                              setDraft({
                                ...draft,
                                from: Number(e.target.value),
                              })
                            }
                            className="h-9 w-16 rounded-[8px] border border-[var(--border-plain)] bg-[var(--input-bg)] px-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--focus-ring)]"
                          />
                          <span aria-hidden="true">–</span>
                          <label className="sr-only" htmlFor={`${member.id}-to`}>
                            Sector to
                          </label>
                          <input
                            id={`${member.id}-to`}
                            type="number"
                            min={1}
                            max={7}
                            value={draft.to}
                            onChange={(e) =>
                              setDraft({ ...draft, to: Number(e.target.value) })
                            }
                            className="h-9 w-16 rounded-[8px] border border-[var(--border-plain)] bg-[var(--input-bg)] px-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--focus-ring)]"
                          />
                        </div>
                      ) : null}
                    </div>
                  ) : (
                    <span>{scopeLabel(member.scope)}</span>
                  )}
                </TableCell>
                <TableCell>
                  {editing ? (
                    <Select
                      value={draft.permissions}
                      onValueChange={(v) =>
                        setDraft({ ...draft, permissions: v as Permission })
                      }
                    >
                      <SelectTrigger
                        className="h-9 w-44"
                        aria-label={`Permissions for ${member.fullName}`}
                      >
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {PERMISSION_OPTIONS.map((perm) => (
                          <SelectItem key={perm} value={perm}>
                            {perm}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  ) : (
                    <span>{member.permissions}</span>
                  )}
                </TableCell>
                <TableCell className="text-right">
                  {editing ? (
                    <div className="flex justify-end gap-1">
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8"
                        aria-label={`Save changes for ${member.fullName}`}
                        onClick={() => saveEdit(member.id)}
                      >
                        <Check className="h-4 w-4" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 text-ink-secondary"
                        aria-label={`Cancel editing ${member.fullName}`}
                        onClick={cancelEdit}
                      >
                        <X className="h-4 w-4" />
                      </Button>
                    </div>
                  ) : (
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8"
                      aria-label={`Edit ${member.fullName}`}
                      onClick={() => startEdit(member.id)}
                    >
                      <Pencil className="h-4 w-4" />
                    </Button>
                  )}
                </TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
    </div>
  );
}
