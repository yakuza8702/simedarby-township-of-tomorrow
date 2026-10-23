"use client";

// P2-SPEC §1/§6 — Settings › sub-nav (Categories / SLA policies / Templates /
// Roles / Branding) with Roles as the active default and a permission-denied
// demo for Viewer attempts at SLA policies.
import { Eye, EyeOff, ShieldAlert } from "lucide-react";
import * as React from "react";

import { CATEGORIES } from "@/lib/data/reports";
import { slaPolicies } from "@/lib/data/roles";
import { templates } from "@/lib/data/templates";
import { useStore } from "@/lib/store";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { PermissionModal } from "@/components/roles/PermissionModal";
import { RolesTable } from "@/components/roles/RolesTable";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

const SUB_NAV = [
  "Categories",
  "SLA policies",
  "Templates",
  "Roles",
  "Branding",
] as const;

type SubNavKey = (typeof SUB_NAV)[number];

const TOKENS: Array<[string, string]> = [
  ["Primary green", "#2E7D32"],
  ["Success", "#388E3C"],
  ["Warn", "#F9A825"],
  ["Review blue", "#1E88E5"],
  ["Error", "#B71C1C"],
  ["Sidebar tint", "#F1F8E9"],
];

export default function RolesSettingsPage() {
  const store = useStore();
  const [tab, setTab] = React.useState<SubNavKey>("Roles");
  const [deniedOpen, setDeniedOpen] = React.useState(false);

  const isViewer = store.viewAsViewer;

  const handleTabChange = (next: string) => {
    if (next === "SLA policies" && isViewer) {
      setDeniedOpen(true);
      return; // keep Roles active behind the modal
    }
    setTab(next as SubNavKey);
  };

  return (
    <div className="space-y-5 pb-10">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-xl font-bold text-ink-primary">Settings</h2>
          <p className="text-sm text-ink-secondary">
            Roles, policies and templates for the council operations console
          </p>
        </div>
        <Button
          variant={isViewer ? "secondary" : "outline"}
          size="sm"
          aria-pressed={isViewer}
          onClick={() => store.setViewAsViewer(!isViewer)}
        >
          {isViewer ? (
            <>
              <EyeOff className="h-4 w-4" aria-hidden="true" />
              Viewing as Viewer — exit preview
            </>
          ) : (
            <>
              <Eye className="h-4 w-4" aria-hidden="true" />
              Preview permissions as Viewer
            </>
          )}
        </Button>
      </div>

      <Tabs
        value={tab}
        onValueChange={handleTabChange}
        aria-label="Settings sections"
      >
        <TabsList className="h-auto flex-wrap justify-start">
          {SUB_NAV.map((item) => (
            <TabsTrigger key={item} value={item} className="text-sm">
              {item}
            </TabsTrigger>
          ))}
        </TabsList>

        <TabsContent value="Categories">
          <Card>
            <CardContent className="p-5">
              <h3 className="text-sm font-semibold text-ink-primary">
                Report categories
              </h3>
              <p className="mt-1 text-xs text-ink-secondary">
                Categories residents can pick in the app; order drives the
                filter menu.
              </p>
              <ul className="mt-4 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                {CATEGORIES.map((category) => {
                  const count = store.reports.filter(
                    (r) => r.category === category
                  ).length;
                  return (
                    <li
                      key={category}
                      className="flex items-center justify-between rounded-[8px] border border-[var(--border-plain)] bg-[var(--input-bg)] px-3 py-2 text-sm"
                    >
                      <span className="text-ink-primary">{category}</span>
                      <Badge className="rounded-full bg-[var(--active-tint)] text-[var(--green-text)]">
                        {count} open
                      </Badge>
                    </li>
                  );
                })}
              </ul>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="SLA policies">
          <Card>
            <CardContent className="p-5">
              <h3 className="text-sm font-semibold text-ink-primary">
                SLA policies
              </h3>
              <p className="mt-1 text-xs text-ink-secondary">
                First-response and resolution windows per priority. Editing
                requires Admin rights.
              </p>
              <div className="mt-4 overflow-hidden rounded-[12px] border border-[var(--border-plain)]">
                <Table>
                  <TableHeader>
                    <TableRow className="hover:bg-transparent">
                      <TableHead scope="col">Priority</TableHead>
                      <TableHead scope="col">First response</TableHead>
                      <TableHead scope="col">Resolution</TableHead>
                      <TableHead scope="col">Escalation</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {slaPolicies.map((policy) => (
                      <TableRow key={policy.priority}>
                        <TableCell className="font-medium">
                          {policy.priority}
                        </TableCell>
                        <TableCell>{policy.firstResponse}</TableCell>
                        <TableCell>{policy.resolution}</TableCell>
                        <TableCell className="text-ink-secondary">
                          {policy.escalation}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="Templates">
          <Card>
            <CardContent className="p-5">
              <h3 className="text-sm font-semibold text-ink-primary">
                Broadcast templates
              </h3>
              <p className="mt-1 text-xs text-ink-secondary">
                Approved message templates; edits are logged to the audit trail.
              </p>
              <div className="mt-4 overflow-hidden rounded-[12px] border border-[var(--border-plain)]">
                <Table>
                  <TableHeader>
                    <TableRow className="hover:bg-transparent">
                      <TableHead scope="col">ID</TableHead>
                      <TableHead scope="col">Name</TableHead>
                      <TableHead scope="col">Channel</TableHead>
                      <TableHead scope="col">Version</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {templates.map((template) => (
                      <TableRow key={template.id}>
                        <TableCell className="font-mono text-xs">
                          {template.id}
                        </TableCell>
                        <TableCell className="font-medium">
                          {template.name}
                        </TableCell>
                        <TableCell>{template.channel}</TableCell>
                        <TableCell>v{template.version}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="Roles">
          <RolesTable />
        </TabsContent>

        <TabsContent value="Branding">
          <Card>
            <CardContent className="p-5">
              <h3 className="text-sm font-semibold text-ink-primary">
                Branding tokens
              </h3>
              <p className="mt-1 text-xs text-ink-secondary">
                Council console palette — green-community programme.
              </p>
              <ul className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {TOKENS.map(([name, hex]) => (
                  <li
                    key={hex}
                    className="flex items-center gap-3 rounded-[8px] border border-[var(--border-plain)] bg-[var(--input-bg)] px-3 py-2.5"
                  >
                    <span
                      aria-hidden="true"
                      className="h-8 w-8 rounded-[8px] border border-[var(--border-plain)]"
                      style={{ backgroundColor: hex }}
                    />
                    <div>
                      <p className="text-sm font-medium text-ink-primary">
                        {name}
                      </p>
                      <p className="font-mono text-xs text-ink-secondary">
                        {hex}
                      </p>
                    </div>
                  </li>
                ))}
              </ul>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      {isViewer ? (
        <p
          role="status"
          className="inline-flex items-center gap-2 rounded-[8px] border border-[var(--chip-amber-border)] bg-[var(--chip-amber-bg)] px-3 py-2 text-xs font-medium text-[var(--chip-amber-text)]"
        >
          <ShieldAlert className="h-4 w-4" aria-hidden="true" />
          Viewer preview is on — SLA policy edits will be refused.
        </p>
      ) : null}

      <PermissionModal
        open={deniedOpen}
        onClose={() => {
          setDeniedOpen(false);
          setTab("Roles");
        }}
      />
    </div>
  );
}
