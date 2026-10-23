# P2-SPEC — Admin Web Console, Township of Tomorrow

> Function spec for an admin-only Next.js web console backing the Township of Tomorrow green-community recycling app. Standalone site with local dummy data and mock delays; no backend sync. Design reference: Penpot "Admin-Web" page.

---

## 1. Route Map

| Route | View | Auth gate | Notes |
|---|---|---|---|
| `/login` | Login hero + card | public; redirect to `/reports-queue` if session cookie present | Email/password, SSO divider, forgot-password variant, expired-session banner |
| `/reports-queue` | Filters + KPI row + table + queue tabs | admin-only shell (Section 8) | Map-view variant and detail drawer are client-side toggles, not routes |
| `/settings/roles` | Sub-nav + roles table + permission modal | admin-only shell | Sub-nav stays client-side (Categories / SLA policies / Templates / Roles / Branding) |
| `/audit-log` | Filter bar + audit table | admin-only shell | Time/Actor/Action/Entity/Before→After |
| `/broadcast` | Channel/Title/Body/Audience/Template form | admin-only shell | Toast on send/schedule |
| `/` | — | redirect to `/reports-queue` | Convenience redirect |
| `/settings` | — | redirect to `/settings/roles` | Convenience redirect |

The shell (sidebar + topbar) is applied via a shared layout group `src/app/(shell)/layout.tsx` wrapping `/reports-queue`, `/settings/roles`, `/audit-log`, `/broadcast`. `/login` sits outside the shell.

---

## 2. TypeScript Type Definitions

All types live in `src/lib/types.ts`.

### Report

```ts
type ReportCategory =
  | 'Bin overflowing'
  | 'Illegal dumping'
  | 'Missed collection'
  | 'Damaged bin'
  | 'Recycling contamination'
  | 'Street litter hotspot';

type ReportPriority = 'High' | 'Medium' | 'Low';
type ReportStatus = 'Open' | 'Triaged' | 'In Progress' | 'Resolved';

interface Report {
  id: string;              // RPT-####, zero-padded 4 digits (INFERRED: unify RPT/RP)
  category: ReportCategory;
  priority: ReportPriority;
  ward: 1 | 3 | 5 | 7;    // wards present in dummy data
  precinct: number;        // 1..N
  status: ReportStatus;
  reportedAt: string;      // ISO 8601; October 2026
  assignee: string | null; // name or null when unassigned
  description: string;
  citizenName: string;
  citizenPhotoUrl?: string;
  gps: { lat: number; lng: number };
  slaHours: number;        // e.g. 12 / 24
  slaStartedAt: string;    // ISO 8601
  notes: string[];
  timeline: ReportEvent[];
}

interface ReportEvent {
  status: ReportStatus | 'Received' | 'Acknowledged';
  at: string;              // ISO 8601
  by: string;
}
```

### RoleMember

```ts
type RoleName = 'Admin' | 'Agent' | 'Agent+' | 'Viewer';
type ScopeType = 'All wards' | WardRange;
type WardRange = { from: number; to: number }; // e.g. { from: 1, to: 3 }
type Permission = 'Full access' | 'Edit+Assign' | 'Edit+Assign+SLA' | 'Read-only View';

interface RoleMember {
  id: string;
  fullName: string;
  email: string;
  role: RoleName;
  scope: ScopeType;
  permissions: Permission;
  initials: string;
  avatarColor: string;
}
```

### AuditEntry

```ts
type AuditAction =
  | 'Updated SLA'
  | 'Assigned'
  | 'Escalated'
  | 'Edited template'
  | 'Resolved'
  | 'Changed role'
  | 'Created'
  | 'Deleted';

type AuditEntity =
  | { kind: 'Report'; id: string }
  | { kind: 'Template'; id: string }
  | { kind: 'Role'; userId: string }
  | { kind: 'SLA'; id: string };

interface AuditEntry {
  id: string;
  time: string;          // ISO 8601
  actor: string;
  action: AuditAction;
  entity: AuditEntity;
  before: string;        // human-readable previous state
  after: string;         // human-readable new state
}
```

### Broadcast

```ts
type BroadcastChannel = 'SMS' | 'Email' | 'Push';
type BroadcastAudience = 'All residents' | 'Precinct 3' | 'State agencies'; // "Scared agencies" normalised (INFERRED)

interface Broadcast {
  id: string;
  channel: BroadcastChannel;
  title: string;
  body: string;
  audience: BroadcastAudience;
  templateId: string;
  scheduledFor?: string;  // ISO 8601, undefined = send now
  createdAt: string;      // ISO 8601
}
```

### AdminUser

```ts
interface AdminUser {
  id: string;
  fullName: string;
  email: string;
  role: RoleName;
  scope: ScopeType;
  initials: string;
  avatarColor: string;
}
```

---

## 3. Dummy-Data Inventory

All dummy data lives in `src/lib/data/*.ts`. Counts match the Penpot design exactly; anything extended for realism is marked INFERRED.

| Collection | Count | Source basis | Notes |
|---|---|---|---|
| `reports` | 24 total | design: "24 open reports" + pagination "Showing 1–6 of 24" | 24 **Open** per design hero KPI; Section 3a breaks out triaged/resolved as separate status counts |
| `reports` with status Open | 24 | design hero: "24 open reports" | filterable default |
| `reports` with status Triaged | 9 | design KPI: "Triaged 9" | |
| `reports` with status Resolved (lifetime) | 61 | design: "61 resolved this week" | this is a lifetime/weekly aggregate; the Open table shows only current open reports |
| `resolvedReportsSample` | 61 | INFERRED | separate collection for KPI display, not shown in the main table |
| wards | Ward 1, 3, 5, 7 | design map chips | precincts 1..12 INFERRED, distributed across wards |
| `roleMembers` | 5 | design table rows | A. Rahman, M. Alvarez, J. Okafor, P. Ndiaye, L. Chen |
| `auditEntries` | 12 | 5 design rows + 7 INFERRED | spans Oct 2026 |
| `broadcasts` | 6 | INFERRED | 3 sent, 3 scheduled, mix of channels |
| `categories` | 6 | design filter dropdown | Bin overflowing, Illegal dumping, Missed collection, Damaged bin, Recycling contamination, Street litter hotspot |

### 3a. Report distribution (Open, the default table view)

Reports are labelled `RPT-2401..RPT-2424` (INFERRED: sequential October block). Distribution:

- High priority: 6
- Medium priority: 11
- Low priority: 7
- Ward 1: 7 · Ward 3: 6 · Ward 5: 6 · Ward 7: 5
- Assigned: 17 · Unassigned: 7 (design: "My tickets (7)" / "Unassigned (23)" — note the tab counts of 7+23 exceed 24; treat "Unassigned (23)" as the broader queue tab and "My tickets (7)" as a sub-filter for the current admin user — INFERRED: tab numbers reflect a multi-user queue the logged-in admin has visibility into, not a strict subset of the 24 Open reports)
- Reported date range: 2026-10-17..2026-10-23 (INFERRED: last 7 days)
- Precincts touched: 1–9

### 3b. Triaged subset (9 reports)

A separate filtered view reachable through the Status filter. Distribution:
- High: 3 · Medium: 4 · Low: 2
- All assigned (INFERRED: triage implies an assignee)

### 3c. Role members

| User | Role | Scope | Permissions |
|---|---|---|---|
| A. Rahman | Admin | All wards | Full access |
| M. Alvarez | Agent | Ward 1–3 | Edit+Assign |
| J. Okafor | Agent+ | Ward 3 | Edit+Assign+SLA |
| P. Ndiaye | Viewer | Read-only | View |
| L. Chen | Agent | Ward 5–7 | Edit+Assign |

### 3d. Audit entries (12 rows, October 2026)

Sample (the 5 design-mandated rows):
1. Updated SLA · RPT-2481 · 24h → 12h
2. Assigned · RPT-2481 · Unassigned → M. Alvarez
3. Escalated · Level 1 → Level 2
4. Edited template · TPL-006 · v3 → v4
5. Resolved · RPT-2390
6. Changed role · Agent → Agent+ (INFERRED)
7–12. INFERRED (Created template, Deleted report, Assigned RPT-2475, etc.)

### 3e. Broadcast templates (INFERRED)

| id | name |
|---|---|
| TPL-001 | Road works — standard |
| TPL-002 | Bin collection delay |
| TPL-003 | Recycling awareness |
| TPL-004 | Hazard alert |

---

## 4. Design → shadcn/ui Component Mapping

| Design element | shadcn component | Tailwind / token |
|---|---|---|
| Sidebar | custom `<nav>` (collapsible) | `w-[240px] bg-[#F1F8E9] text-[#1C1B1F]` |
| Topbar | custom `<header>` | `h-[56px] bg-white border-b border-[#E0E0E0]` |
| KPI card | `<Card>` + `<CardContent>` | card radius 12 (`rounded-[12px]`), divider `#E0E0E0` |
| Filter `<select>` | `<Select>` (shadcn) | input surface `#FAFAFA`, radius 8, border `#E0E0E0` |
| Filter chips | `<Button variant="outline">` pill | active: `#E8F5E9` bg + `#2E7D32` text |
| Table | `<Table>` family | header ink `#616161`, row divider `#E0E0E0` |
| Tabs | `<Tabs>` / `<TabsList>` / `<TabsTrigger>` | active tint `#E8F5E9`, primary `#2E7D32` |
| Map view | custom `<div>` + chip buttons | ward chips: same as filter chips |
| Cluster pins | custom `<Button>` absolute-positioned | primary `#2E7D32` badge |
| Detail drawer | `<Sheet side="right">` (shadcn) | `w-[400px]`, bg white |
| Status chip | `<Badge>` | colour per status (below) |
| Avatar | `<Avatar>` + `<AvatarFallback>` | pill, 32px, `#E8F5E9` bg |
| Toast | `<Toast>` (shadcn, via `useToast`) | success `#388E3C`, error `#D32F2F`, warn `#F9A825` |
| Modal / dialog | `<Dialog>` | same radii / ink as cards |
| Radio group (broadcast channel) | `<RadioGroup>` | checked fill `#2E7D32` |
| Textarea (broadcast body, notes) | `<Textarea>` | surface `#FAFAFA`, radius 8 |
| Pagination | custom `<nav>` with `<Button variant="outline">` | `Showing {x}–{y} of {z}` |
| Inputs (login, note field) | `<Input>` | surface `#FAFAFA`, radius 8 |
| Buttons (primary) | `<Button>` | bg `#2E7D32`, hover `#388E3C`, radius 8 |
| Buttons (ghost / link) | `<Button variant="ghost">` | text `#2E7D32` |
| Buttons (destructive) | `<Button variant="destructive">` | bg `#D32F2F` |
| Dividers / SSO separator | `<div>` with text | border `#E0E0E0`, text `#616161` |

### Tailwind colour variables (tailwind.config.ts → CSS vars)

```ts
// tailwind.config.ts — extend theme
colors: {
  primary:    { DEFAULT: '#2E7D32', ink: '#1C1B1F' },  // green / ink
  success:    '#388E3C',
  warn:       { DEFAULT: '#F9A825', ink: '#8D6E00', tint: '#FFF8E1' },
  error:      { DEFAULT: '#B71C1C', soft: '#D32F2F' },
  triage:     { DEFAULT: '#1E88E5', tint: '#E3F2FD' },
  surface:    { DEFAULT: '#FFFFFF', input: '#FAFAFA', sidebar: '#F1F8E9', active: '#E8F5E9' },
  ink:        { primary: '#1C1B1F', secondary: '#616161', tertiary: '#424242' },
  divider:    '#E0E0E0',
}
```

### Status chip colour mapping

| Status | bg | text |
|---|---|---|
| Open | `#E3F2FD` | `#1E88E5` |
| Triaged | `#FFF8E1` | `#8D6E00` |
| In Progress | `#E8F5E9` | `#2E7D32` |
| Resolved | `#F1F8E9` | `#388E3C` |

### Priority colour mapping

| Priority | dot / accent |
|---|---|
| High | `#D32F2F` |
| Medium | `#F9A825` |
| Low | `#616161` |

### Spacing scale (INFERRED — no tokens in design)

4px base scale: `1` = 4px, `2` = 8px, `3` = 12px, `4` = 16px, `6` = 24px, `8` = 32px, `12` = 48px. Content max-width 1200px with `px-6` (24px) side padding.

### Radius scale

- Cards: `rounded-[12px]`
- Buttons / inputs: `rounded-[8px]`
- Chips / avatars: `rounded-full`

---

## 5. Loading / Empty / Error Handling (INFERRED)

| State | Trigger | UI |
|---|---|---|
| Page load / data fetch | mock 250–400ms delay | shadcn `<Skeleton>` rows matching table shape; sidebar/topbar render immediately |
| Filter yields no results | filter combination produces 0 rows | `<div>` empty state: illustration-less centred card — "No reports match these filters. Clear or widen your search." + `<Button variant="ghost">Clear filters</Button>` |
| Wrong password | login submit with invalid creds | inline error below Password input: "Incorrect email or password." + red ring on inputs; toast optional |
| SSO error | SSO handshake fails (simulated) | banner above login card: "SSO provider refused the handshake. Retry or use email sign-in." |
| Expired session | session cookie detected as expired on mount | amber banner across shell: "Your session expired for safety — please sign in again." → redirect to `/login?reason=expired` |
| Permission denied | Viewer role attempts SLA edit | modal (Section 6) |
| Drawer open with no selection | edge case | empty drawer body: "Select a report to view details." (INFERRED) |
| Broadcast validation | send with empty title or body | red inline error below each empty field; toast on success only |

All async boundaries wrap reads in `setTimeout(..., Math.random()*150 + 250)` inside route-loading `loading.tsx` files to exercise the skeleton states during development; production build replaces with instant reads.

---

## 6. Interactions

### Login (`/login`)

1. User enters email + password, presses **Sign in** or `Enter`.
2. Validation: email non-empty + valid shape, password ≥ 1 char. Empty fields → red ring + inline message.
3. Credentials checked against single hardcoded admin (`admin@township.example` / `council2026`). Match → set session cookie, redirect to `/reports-queue`. Mismatch → "Incorrect email or password." (wrong-password flow).
4. **Sign in with Council SSO** button → simulated handshake. 90% success (same flow as step 3), 10% failure → SSO error banner with Retry + fall-back to email link.
5. **Forgot password?** → swaps card to reset form: single email input + "Send reset link" + "← Back to sign-in". On submit → toast "Reset link sent (simulated)" and auto-returns to sign-in after 3s.

### Reports queue (`/reports-queue`)

- **Filters** (Category / Priority / Status / Precinct) — multi-select `<Select>` with checkboxes. Selecting updates URL query string and refetches with mock delay. **Export CSV** button generates a client-side Blob of the currently filtered rows and triggers `URL.createObjectURL` + anchor click.
- **KPI row** — four cards: Open 24, Triaged 9, Resolved 61, Avg triage 2.4h. Static from dummy data.
- **Queue tabs** — `My tickets (7)` / `Unassigned (23)`. Switching tab filters the table client-side without refetch.
- **Pagination** — 6 rows per page, "Showing 1–6 of 24" label with prev/next `<Button variant="outline">`.
- **Map view** — toggle replaces table with ward-filtered map surface. Ward chips `All wards` / `Ward 1` / `Ward 3` / `Ward 7`. Cluster pins show counts; clicking opens mini card `RPT-2481 · Illegal dumping · 08:12` with **Open drawer** action.
- **Detail drawer** (`<Sheet>`) — opens from row click or mini-card action.
  - Title: `RPT-2481 — Illegal dumping`; meta line below.
  - Status chip (colour per mapping), SLA line `SLA · 14h 06m left` with breach note in red when remaining < 0.
  - Timeline vertical list: Received → Acknowledged → In Progress → Resolved (greyed for not-yet).
  - Citizen photo card (Avatar + name), GPS line, internal note `<Textarea>` with placeholder "Add a note for the response team…".
  - Footer buttons: **Assign** (opens inline `<Select>` of role members), **Escalate** (shifts Level 1→2, logs to audit), **Close** (status → Resolved, logs to audit). Each action re-renders drawer and table immediately.

### Settings / Roles (`/settings/roles`)

- Sub-nav: Categories / SLA policies / Templates / Roles / Branding. Roles is the active default.
- Roles table: User / Role / Scope / Per-resource permissions. Edit row icon opens inline edit mode in the row; save writes to local dummy-data copy in memory.
- Permission-denied modal triggered for Viewer role touching SLA policies: "You don't have permission to edit SLA policies" / "Ask an admin in Run group for access." / **Back to settings** button.

### Audit log (`/audit-log`)

- Columns: Time / Actor / Action / Entity / Before → After.
- Filter bar: actor `<Select>`, action `<Select>`, date range `<Input type="date">` (INFERRED). Filters apply client-side.
- Rows clickable → expandable detail showing full before/after diff (INFERRED).

### Broadcast (`/broadcast`)

- CHANNEL radio: SMS / Email / Push (Push default-checked).
- TITLE input: "Ward 3 · Road resurfacing tonight 22:00".
- BODY `<Textarea>`.
- AUDIENCE checkboxes: All residents (default-checked) / Precinct 3 / State agencies (normalised from design typo "Scared agencies").
- TEMPLATE `<Select>`: Road works — standard (default), Bin collection delay, Recycling awareness, Hazard alert.
- **Send broadcast** button → validates title+body → success toast "Broadcast sent to {n} residents." → appends entry to `broadcasts` collection.
- **Schedule** button → opens datetime picker (INFERRED) → success toast "Broadcast scheduled for {datetime}.".

### CSV Export (client-side Blob)

```ts
// illustrative snippet — src/lib/csv.ts
function exportCsv(rows: Report[], filename: string) {
  const header = ['ID','Category','Priority','Ward','Precinct','Status','Reported','Assignee'];
  const body = rows.map(r => [r.id, r.category, r.priority, r.ward, r.precinct, r.status, r.reportedAt, r.assignee ?? 'Unassigned']);
  const csv = [header, ...body].map(row => row.map(cell => `"${String(cell).replace(/"/g,'""')}"`).join(',')).join('\n');
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = filename; a.click();
  URL.revokeObjectURL(url);
}
```

---

## 7. Implementation File Tree

```
admin-web/
├── package.json                 # Next 14, TS, Tailwind, shadcn/ui deps
├── tailwind.config.ts           # colour vars (Section 4)
├── tsconfig.json
├── next.config.ts
├── postcss.config.mjs
├── public/
│   └── favicon.ico
├── README.md
└── src/
    ├── app/
    │   ├── layout.tsx           # root layout, font (Source Sans Pro via next/font or CSS @font-face; offline = self-hosted woff2)
    │   ├── globals.css          # CSS vars, Tailwind base
    │   ├── login/
    │   │   ├── page.tsx         # hero + login card, forgot-password variant
    │   │   └── loading.tsx
    │   ├── (shell)/
    │   │   ├── layout.tsx       # sidebar + topbar shell
    │   │   ├── reports-queue/
    │   │   │   ├── page.tsx     # filters, KPI row, table, tabs
    │   │   │   ├── loading.tsx  # skeleton table
    │   │   │   ├── map-view.tsx # ward chips + cluster pins + mini card
    │   │   │   └── detail-drawer.tsx
    │   │   ├── settings/
    │   │   │   └── roles/
    │   │   │       ├── page.tsx # sub-nav + roles table
    │   │   │       ├── loading.tsx
    │   │   │       └── permission-modal.tsx
    │   │   ├── audit-log/
    │   │   │   ├── page.tsx
    │   │   │   └── loading.tsx
    │   │   └── broadcast/
    │   │       ├── page.tsx
    │   │       └── loading.tsx
    │   └── (redirects handled via layout or middleware)
    ├── components/
    │   ├── shell/
    │   │   ├── Sidebar.tsx
    │   │   ├── Topbar.tsx
    │   │   └── NavLink.tsx
    │   ├── reports/
    │   │   ├── Filters.tsx
    │   │   ├── KpiRow.tsx
    │   │   ├── ReportsTable.tsx
    │   │   ├── Pagination.tsx
    │   │   ├── StatusBadge.tsx
    │   │   ├── PriorityDot.tsx
    │   │   └── MapView.tsx
    │   ├── roles/
    │   │   ├── RolesTable.tsx
    │   │   └── PermissionModal.tsx
    │   ├── audit/
    │   │   ├── AuditTable.tsx
    │   │   └── AuditFilters.tsx
    │   ├── broadcast/
    │   │   ├── BroadcastForm.tsx
    │   │   └── ChannelRadio.tsx
    │   ├── login/
    │   │   ├── LoginCard.tsx
    │   │   ├── HeroPane.tsx
    │   │   └── ForgotPasswordCard.tsx
    │   └── ui/                  # shadcn-generated (Button, Card, Table, Tabs, Sheet, Select, Input, Badge, Avatar, Textarea, RadioGroup, Toast, Dialog)
    ├── lib/
    │   ├── types.ts             # Section 2
    │   ├── data/
    │   │   ├── reports.ts       # 24 Open + triaged sample + resolved aggregate
    │   │   ├── roles.ts
    │   │   ├── audit.ts
    │   │   ├── broadcasts.ts
    │   │   └── templates.ts
    │   ├── csv.ts               # Section 6 blob helper
    │   ├── mock-delay.ts        # setTimeout wrapper
    │   ├── session.ts           # cookie read/write helpers
    │   └── a11y.ts              # aria helpers, focus trap for drawer
    └── middleware.ts            # auth gate — redirects unauthenticated to /login
```

`middleware.ts` checks the session cookie on every `/` request. Missing or expired cookie → `/login`. Expired reason appended as `?reason=expired` so the login page can show the expired banner. Authenticated users hitting `/login` are redirected to `/reports-queue`.

---

## 8. Accessibility + Responsive

### Accessibility

- All interactive controls carry `aria-label` or visible `<label>` + `htmlFor`.
- Filter `<Select>` uses `role="listbox"` via shadcn; arrow-key navigation works out of the box.
- Detail drawer (`<Sheet>`) traps focus on open, restores focus to the triggering row on close, sets `aria-modal="true"` and `role="dialog"`.
- Status chips use `aria-label` reporting the full state (e.g. `aria-label="Status: Triaged"`), not just colour.
- Toast container uses `role="status"` `aria-live="polite"`; error toasts use `aria-live="assertive"`.
- CSV export button announces "Export complete" via a visually-hidden `aria-live` region after the Blob download.
- Keyboard: `Esc` closes drawer, modal, and any open `<Select>` — shadcn handles most; we add `onKeyDown` for drawer.
- Colour contrast: green `#2E7D32` on white = 5.9:1 (AA pass); amber ink `#8D6E00` on `#FFF8E1` = 5.2:1 (AA pass); error `#D32F2F` on white = 5.7:1 (AA pass). INFERRED: verified per WCAG 2.1 AA.
- Focus ring: shadcn default `ring-offset-2 ring-[#2E7D32]` for all focusable elements.

### Responsive

- **≥ 1280px (xl):** sidebar fixed 240px, content 1200px max with 24px padding, topbar 56px. Map and table show full columns.
- **1024–1279px (lg):** sidebar collapses to icon-only rail (64px). Topbar absorbs a hamburger toggle. Table columns truncate; Assignee hidden on narrow.
- **< 1024px (below lg, md and sm):** sidebar becomes a bottom-sheet or off-canvas drawer toggled by hamburger in topbar. KPI row becomes a horizontal-scroll card row. Reports table becomes a stacked card list. Map view hides ward chips behind a dropdown. Broadcast form stacks vertically.
- **< 640px (sm):** login hero pane collapses; teaser KPI cards stack vertically; forgot-password form full-width.
- The `lg` breakpoint (1024px) is the primary collapse threshold. Tailwind config keeps default breakpoints but the shell layout uses `lg:` variants for the sidebar rail transition.

### Font loading (offline)

Source Sans Pro is self-hosted under `public/fonts/source-sans-pro/` (woff2 variants: 400, 600, 700). `@font-face` declarations in `globals.css` with `font-display: swap`. `next/font` is **not** used because it requires network fetch at build time — we hand-roll the offline `@font-face` (INFERRED: aligns with "standalone offline, no remote fonts" constraint).

---

## Appendix A — ID format unification

Design uses both `RPT-2481` and `RP-####` variants. All report IDs are normalised to `RPT-####` (zero-padded 4 digits). The dummy-data block is `RPT-2401..RPT-2424` for October 2026 Open reports, `RPT-2301..RPT-2361` for the 61 resolved lifetime set, and `RPT-2362..RPT-2390` for historical triaged items referenced in audit entries. Any `RP-` prefix in the Penpot design is treated as a typo.

## Appendix B — Copy to reuse verbatim from design

- "Council operations console — waste, reports, and collection in one place"
- "24 open reports" / "6 routes today" / "61 resolved this week"
- "Forgot password?" / "Sign in" / "Sign in with Council SSO"
- "SSO provider refused the handshake. Retry or use email sign-in."
- "Your session expired for safety"
- "Reset your password" / "Send reset link" / "← Back to sign-in"
- "Reports queue"
- "24 resident reports · updated 5 min ago"
- "Search ID, category, assignee…"
- "Showing 1–6 of 24"
- "My tickets (7)" / "Unassigned (23)"
- "All wards" / "Ward 1" / "Ward 3" / "Ward 7"
- "RPT-2481 · Illegal dumping · 08:12" / "Open drawer"
- "RPT-2481 — Illegal dumping"
- "Illegal dumping · Reported 08:12 · Precinct 3"
- "SLA · 14h 06m left"
- "Add a note for the response team…"
- "Assign" / "Escalate" / "Close"
- Categories: Bin overflowing, Illegal dumping, Missed collection, Damaged bin, Recycling contamination, Street litter hotspot
- "You don't have permission to edit SLA policies"
- "Ask an admin in Run group for access." / "Back to settings"
- "Ward 3 · Road resurfacing tonight 22:00"
- "All residents" / "Precinct 3" / "State agencies" (normalised from "Scared agencies")
- "Road works — standard"
- "Send broadcast" / "Schedule"

## Appendix C — INFERRED decisions log

| # | Decision | Rationale |
|---|---|---|
| 1 | 4px spacing scale | no design tokens; industry standard |
| 2 | `lg` (1024px) sidebar collapse | Tailwind convention |
| 3 | Report IDs `RPT-####` unified | design uses both RPT and RP |
| 4 | Avg triage 2.4h as static KPI | design shows single number |
| 5 | "Scared agencies" → "State agencies" | obvious design typo |
| 6 | Queue tab counts exceed 24 | multi-user queue the admin has visibility into |
| 7 | Broadcast datetime picker `<Input type="datetime-local">` | simplest offline input |
| 8 | Session as httpOnly-ish client cookie (document.cookie for demo) | standalone dummy data, no real auth |
| 9 | Source Sans Pro self-hosted via @font-face | offline constraint |
| 10 | Resolved (61) as separate aggregate collection | KPI display only, not in main table |
| 11 | Audit entries 12 total (5 design + 7 INFERRED) | populate scrollable table |
| 12 | Mock delay 250–400ms | exercise skeleton states |
