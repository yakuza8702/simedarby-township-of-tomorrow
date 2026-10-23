# Township of Tomorrow Admin Web Console

Council operations console for the Township of Tomorrow gated-community
recycling app: Next.js 14 (App Router), TypeScript, Tailwind, shadcn-style UI.
Every row comes from typed local dummy data. There is no backend behind it, no
account system, no database. The team walks reviewers through triage, planning
and settings screens on this build before the hackathon submission.

Function spec: [`./P2-SPEC.md`](./P2-SPEC.md).

## Warning: no real data

Every row, report, user and broadcast in this console is invented demo data in
`src/lib/data/`, modelling October 2026 across Sectors 1/3/5/7 of a fictional
township. No resident, crew, property or report from a real community appears
anywhere in it. Do not screenshot this console as evidence of real operations.

## Run

```bash
pnpm install
pnpm dev
# http://localhost:3100
```

This container's `/tmp` is a small read-only tmpfs. Point pnpm and node at the
workspace caches before the build:

```bash
TMPDIR=/workspace/.agent-tmp
NPM_CONFIG_CACHE=/workspace/.npm-cache
```

Production:

```bash
pnpm build
pnpm start -H 0.0.0.0
# still port 3100; -H binds the dev-machine network interface too
```

## Demo credentials

| Field | Value |
|---|---|
| Email | `admin@township.example` |
| Password | `council2026` |

Login screen states worth testing:

| State | How to trigger |
|---|---|
| Wrong password | any other password, inline "Incorrect email or password." |
| Forgot password | "Forgot password?" under the form |
| Council SSO | "Sign in with Council SSO" button |
| SSO refusal path | the button, or force it with `/login?demo=sso-error` |
| Session expired | open `/login?reason=expired` after the cookie is dropped |

## Route tour

| Route | What it is |
|---|---|
| `/login` | Login hero and card, with SSO, forgot-password and expired states |
| `/reports-queue` | Triage console: filters, KPI row, queue tabs, table and OSM map view, detail drawer |
| `/sectors` | Sector boundary cards, weekly collection calendar, crew rosters. The old name was "precinct"; the product language is now Sector |
| `/precincts` | Legacy path, redirects to `/sectors` |
| `/collection-routes` | Route table RT-1..RT-6 plus the planning panel (Assign, Optimise order) |
| `/users` | Staff table, access-review panel, read-only access preview modal |
| `/settings/roles` | Settings sub-nav, roles table, permission-denied modal demo |
| `/audit-log` | Filter bar and audit table with Before to After diffs |
| `/broadcast` | Channel, title, body, audience and template composer with toasts |
| `/` | Redirects to `/reports-queue` |
| `/settings` | Redirects to `/settings/roles` |

## Map (reports queue)

The map pulls standard OpenStreetMap raster tiles at runtime from the browser
(`https://tile.openstreetmap.org/{z}/{x}/{y}.png`). Those tiles are the only
remote asset this console touches, and fonts, images and everything else ship
local. Each Open or In review report gets a single pin, coloured by priority,
and neighbouring pins merge into numbered cluster circles. Click a pin or a
cluster and the detail drawer a table row opens comes up instead. Tiles that
fail to load degrade the map to a grey grid, while pins, clusters, zoom and
the drawer stay interactive.

## Dark and light mode

A sun/moon toggle sits in the topbar, and light is the default. The choice is
stored in `localStorage` under `township-theme`. A tiny inline script in
`src/app/layout.tsx` applies it before first paint, so there is no flash of the
wrong theme. Dark surfaces, borders and text come from CSS custom properties in
`src/app/globals.css`, while brand greens and component logic stay identical
in both themes.

## GitHub Actions

The GitHub Actions workflow that builds and publishes the Android APK lives in
the Flutter app, on the Android branch of this repo rather than here. The
admin-web branch ships source only.

## Deviations from spec

- **System fonts**: P2-SPEC §8 / Appendix C #9 asks for self-hosted Source Sans
  Pro woff2. The console uses a system sans font stack instead, so no font
  files are downloaded or shipped.
- **OSM tiles allowed on the map**: the "no remote assets" rule is relaxed for
  the reports map only, because the data source the user asked for is OSM
  raster tiles, matching the Android counterpart's flutter_map setup.
- **Leaflet as the map dependency**: `leaflet` plus `@types/leaflet` is the one
  runtime dependency added for this. The map component loads through
  `next/dynamic` with `ssr: false`, so the build stays static-safe. Clustering
  is hand-rolled, there is no cluster library.
- **Route rename with legacy redirect**: the spec's `/precincts` route was
  renamed to `/sectors`. The old path still works through a temporary redirect
  defined in `next.config.mjs`, so bookmarks and muscle memory stay valid.

## Notes

- The demo-data banner in the sidebar footer ("Offline demo data") is a constant
  reminder that this build is not connected to anything.
- Sector chips on the map (All sectors, Sector 1, Sector 3, Sector 7) filter the
  pins. Reports flow Open, In review, In Progress, Resolved.
- CSV export is a client-side blob download of the currently filtered table
  rows; nothing is uploaded anywhere.
- The "Preview permissions as Viewer" modal in Settings reproduces the
  permission-denied screen when SLA policies are opened.
- Assign and Optimise order on `/collection-routes` mutate browser state only
  and confirm with a toast. Refreshing the page discards the change.
