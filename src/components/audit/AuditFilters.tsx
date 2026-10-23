"use client";

// P2-SPEC §6 — audit filter bar: actor select, action select, date range.
import { Download } from "lucide-react";
import * as React from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

export interface AuditFilterState {
  actor: string; // "all" | actor name
  action: string; // "all" | action name
  from: string; // yyyy-mm-dd | ""
  to: string; // yyyy-mm-dd | ""
}

interface AuditFiltersProps {
  actors: readonly string[];
  actions: readonly string[];
  state: AuditFilterState;
  onChange: (next: AuditFilterState) => void;
  onExport: () => void;
}

const ALL = "all";

export function AuditFilters({
  actors,
  actions,
  state,
  onChange,
  onExport,
}: AuditFiltersProps) {
  return (
    <section
      aria-label="Audit filters"
      className="flex flex-wrap items-end gap-2"
    >
      <div className="w-44">
        <Label htmlFor="audit-actor" className="mb-1 block text-xs text-ink-secondary">
          Actor
        </Label>
        <Select
          value={state.actor}
          onValueChange={(actor) => onChange({ ...state, actor })}
        >
          <SelectTrigger id="audit-actor" className="h-9" aria-label="Filter by actor">
            <SelectValue placeholder="All actors" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All actors</SelectItem>
            {actors.map((actor) => (
              <SelectItem key={actor} value={actor}>
                {actor}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="w-44">
        <Label htmlFor="audit-action" className="mb-1 block text-xs text-ink-secondary">
          Action
        </Label>
        <Select
          value={state.action}
          onValueChange={(action) => onChange({ ...state, action })}
        >
          <SelectTrigger
            id="audit-action"
            className="h-9"
            aria-label="Filter by action"
          >
            <SelectValue placeholder="All actions" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All actions</SelectItem>
            {actions.map((action) => (
              <SelectItem key={action} value={action}>
                {action}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="w-40">
        <Label htmlFor="audit-from" className="mb-1 block text-xs text-ink-secondary">
          From
        </Label>
        <Input
          id="audit-from"
          type="date"
          className="h-9"
          value={state.from}
          max={state.to || undefined}
          onChange={(e) => onChange({ ...state, from: e.target.value })}
          aria-label="Filter from date"
        />
      </div>

      <div className="w-40">
        <Label htmlFor="audit-to" className="mb-1 block text-xs text-ink-secondary">
          To
        </Label>
        <Input
          id="audit-to"
          type="date"
          className="h-9"
          value={state.to}
          min={state.from || undefined}
          onChange={(e) => onChange({ ...state, to: e.target.value })}
          aria-label="Filter to date"
        />
      </div>

      <Button
        variant="outline"
        size="sm"
        className="ml-auto h-9 rounded-full text-xs font-medium"
        onClick={onExport}
        aria-label="Export audit log as CSV"
      >
        <Download className="h-4 w-4" aria-hidden="true" />
        Export CSV
      </Button>
    </section>
  );
}
