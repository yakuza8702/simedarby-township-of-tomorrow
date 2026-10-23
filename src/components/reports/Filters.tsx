"use client";

// P2-SPEC §6 — filter bar: search + 4 multi-selects (checkbox lists) + CSV export.
import { ChevronDown, Download, Search, X } from "lucide-react";
import * as React from "react";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { cn } from "@/components/ui/utils";

export interface ReportFilters {
  categories: string[];
  priorities: string[];
  statuses: string[];
  subsectors: string[];
}

export const EMPTY_FILTERS: ReportFilters = {
  categories: [],
  priorities: [],
  statuses: ["Open"],
  subsectors: [],
};

interface MultiSelectFilterProps {
  label: string;
  options: string[];
  selected: string[];
  onChange: (next: string[]) => void;
}

function MultiSelectFilter({
  label,
  options,
  selected,
  onChange,
}: MultiSelectFilterProps) {
  const toggle = (option: string, checked: boolean) => {
    onChange(checked ? [...selected, option] : selected.filter((s) => s !== option));
  };

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          size="sm"
          className={cn(
            "h-9 gap-1.5 rounded-full text-xs font-medium",
            selected.length > 0 &&
              "border-[var(--border-green)] bg-[var(--active-tint)] text-[var(--green-text)]"
          )}
          aria-label={`Filter by ${label}${
            selected.length ? `, ${selected.length} selected` : ""
          }`}
        >
          {label}
          {selected.length > 0 ? (
            <span className="rounded-full bg-[#2E7D32] px-1.5 text-[10px] font-bold text-white">
              {selected.length}
            </span>
          ) : null}
          <ChevronDown className="h-3.5 w-3.5 opacity-70" aria-hidden="true" />
        </Button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-60 p-2">
        <fieldset>
          <legend className="sr-only">{label}</legend>
          <ul className="flex flex-col gap-0.5">
            {options.map((option) => {
              const checked = selected.includes(option);
              return (
                <li key={option}>
                  <label className="flex cursor-pointer items-center gap-2.5 rounded-[6px] px-2 py-1.5 text-sm text-ink-primary hover:bg-[var(--sidebar)]">
                    <Checkbox
                      checked={checked}
                      onCheckedChange={(v) => toggle(option, v === true)}
                      aria-label={option}
                    />
                    <span className="min-w-0 flex-1 truncate">{option}</span>
                  </label>
                </li>
              );
            })}
          </ul>
        </fieldset>
        {selected.length > 0 ? (
          <Button
            variant="ghost"
            size="sm"
            className="mt-1 w-full justify-center text-xs"
            onClick={() => onChange([])}
          >
            Clear {label.toLowerCase()}
          </Button>
        ) : null}
      </PopoverContent>
    </Popover>
  );
}

interface FiltersProps {
  search: string;
  onSearchChange: (v: string) => void;
  filters: ReportFilters;
  onFiltersChange: (next: ReportFilters) => void;
  categoryOptions: string[];
  priorityOptions: string[];
  statusOptions: string[];
  subsectorOptions: string[];
  onExport: () => void;
}

export function Filters({
  search,
  onSearchChange,
  filters,
  onFiltersChange,
  categoryOptions,
  priorityOptions,
  statusOptions,
  subsectorOptions,
  onExport,
}: FiltersProps) {
  const activeChips: Array<{ key: string; label: string; clear: () => void }> =
    [];
  filters.categories.forEach((c) =>
    activeChips.push({
      key: `cat-${c}`,
      label: c,
      clear: () =>
        onFiltersChange({
          ...filters,
          categories: filters.categories.filter((x) => x !== c),
        }),
    })
  );
  filters.priorities.forEach((p) =>
    activeChips.push({
      key: `pri-${p}`,
      label: `${p} priority`,
      clear: () =>
        onFiltersChange({
          ...filters,
          priorities: filters.priorities.filter((x) => x !== p),
        }),
    })
  );
  filters.statuses.forEach((s) =>
    activeChips.push({
      key: `st-${s}`,
      label: s,
      clear: () =>
        onFiltersChange({
          ...filters,
          statuses: filters.statuses.filter((x) => x !== s),
        }),
    })
  );
  filters.subsectors.forEach((p) =>
    activeChips.push({
      key: `pr-${p}`,
      label: `Sub-sector ${p}`,
      clear: () =>
        onFiltersChange({
          ...filters,
          subsectors: filters.subsectors.filter((x) => x !== p),
        }),
    })
  );

  return (
    <section aria-label="Report filters" className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative w-full sm:w-72">
          <Search
            className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-secondary"
            aria-hidden="true"
          />
          <Label htmlFor="report-search" className="sr-only">
            Search reports
          </Label>
          <Input
            id="report-search"
            type="search"
            placeholder="Search ID, category, assignee…"
            className="h-9 rounded-[8px] pl-9 text-sm"
            value={search}
            onChange={(e) => onSearchChange(e.target.value)}
          />
        </div>

        <MultiSelectFilter
          label="Category"
          options={categoryOptions}
          selected={filters.categories}
          onChange={(categories) => onFiltersChange({ ...filters, categories })}
        />
        <MultiSelectFilter
          label="Priority"
          options={priorityOptions}
          selected={filters.priorities}
          onChange={(priorities) => onFiltersChange({ ...filters, priorities })}
        />
        <MultiSelectFilter
          label="Status"
          options={statusOptions}
          selected={filters.statuses}
          onChange={(statuses) => onFiltersChange({ ...filters, statuses })}
        />
        <MultiSelectFilter
          label="Sub-sector"
          options={subsectorOptions}
          selected={filters.subsectors}
          onChange={(subsectors) => onFiltersChange({ ...filters, subsectors })}
        />

        <Button
          variant="outline"
          size="sm"
          onClick={onExport}
          className="ml-auto h-9 rounded-full text-xs font-medium"
          aria-label="Export filtered rows as CSV"
        >
          <Download className="h-4 w-4" aria-hidden="true" />
          Export CSV
        </Button>
      </div>

      {activeChips.length > 0 ? (
        <ul aria-label="Active filters" className="flex flex-wrap gap-1.5">
          {activeChips.map((chip) => (
            <li key={chip.key}>
              <button
                type="button"
                onClick={chip.clear}
                className="inline-flex items-center gap-1 rounded-full border border-[var(--border-green)] bg-[var(--active-tint)] px-2.5 py-0.5 text-xs font-medium text-[var(--green-text)] transition-colors hover:bg-[var(--chip-green-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--focus-ring)]"
                aria-label={`Remove filter ${chip.label}`}
              >
                {chip.label}
                <X className="h-3 w-3" aria-hidden="true" />
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  );
}
