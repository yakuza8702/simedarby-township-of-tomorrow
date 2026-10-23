# DEMO SCRIPT — Township of Tomorrow v0.3.0-b (5 minutes, six beats)

Run-of-show for the on-device demo. Everything runs **on the phone** — airplane
mode is fine and is a feature ("all on-device"), not a problem. Each beat lists
the exact button labels the presenter taps, followed by one fallback line if
on-device detection differs from the expected path. Every beat matches the REAL
app state after the Beat-1 reset.

## Install

```bash
adb install -r /workspace/simedarby-hackathon-student/Township-of-Tomorrow_v0.3.0-b-android-arm64.apk
```

Package: `com.townshipoftomorrow.township_of_tomorrow` · ABI: **arm64-v8a only**
· minSdk 24. Launch: `adb shell monkey -p com.townshipoftomorrow.township_of_tomorrow -c android.intent.category.LAUNCHER 1`

---

## Beat 1 — 0:00 · Set the stage

1. Launch the app from the home screen. Airplane mode ON is fine: say the line —
   "Every scan, report and answer runs on this phone; nothing leaves it."
2. Reset so the demo is deterministic: Home tab → scroll past
   **'My impact this month'** → tap the small grey **'Demo data'** button →
   the toolbox opens on the **'Current counts'** card → tap
   **'Reset demo data'** → confirmation dialog **'Reset demo data?'** → tap
   **'Reset demo data'** again to confirm → SnackBar
   **'Demo data reset — the board is back to the synthetic seed.'**
3. Narrate the line — **"Restore the demo dataset"** — and point at what the
   counts card actually shows (this is a RESTORE, not a clean slate):
   **Hazard reports 4 (3 open)** · **Circular Hub listings 2** ·
   **Collection items 2** · **Cat Dex sightings 3** · **Board posts 9**
   (8 synthetic seed posts + the fixed demo post).

**Fallback (if a prior demo left state behind):** the reset dialog is the
kill-switch — 'Demo data' → 'Reset demo data' → confirm 'Reset demo data'; it
always clears and re-seeds in one step, so the counts above reappear no matter
what the last demoer did.

---

## Beat 2 — 0:45 · Report a problem

1. Home → **'Report a problem'** (quick action) → report form opens.
2. Tap through the form: pick a **category** chip (e.g. 'Bin overflowing'),
   choose a **severity** chip (Low / Medium / High), type one line in
   **'What is wrong there?'**, then tap **'Attach precinct'** — there is NO
   location text field; the button flips into the **'Location: Precinct 1'**
   chip (precinct only, no GPS: the helper text says so out loud). Leave the
   photo empty — that is the point.
3. Tap **'Submit report'** → receipt card appears:
   **'Report logged — this is your receipt'** with
   **'Status: Received — logged just now'** and
   **Ref RP-######** (RP- plus the first six hex digits of a stable FNV-1a
   hash of the report id — the same reference the status cards, board notice
   and command-center drill-down show).
4. Tap **'Track my report'** → status-tracking screen (**'My reports'**) opens
   with the new report highlighted and the Received / In review / **Resolved**
   timeline visible.

**Fallback (if the receipt is not shown immediately):** the report is still
logged locally — reopen it from the receipt's 'Track my report'; the
**Ref RP-######** line is the proof it persisted.

---

## Beat 3 — 1:30 · Scan and recover

1. Bottom nav → **Scan** tab. First contact shows the value-first explainer
   (what the scanner does on-device, what it never does — no upload).
2. Tap **'Allow camera'** → the OS permission prompt appears → tap **Allow**
   while narrating "permission only after an explicit tap, never at boot".
3. Point at one item (a can, a bottle, a box) → detection chip + confidence
   appear → confirm → the item lands in the collection with its category.

**Fallback (if detection differs / camera denied):** the camera-off panel is
the graceful path — **'Import a photo'** runs the same pipeline on a picked
image; after a denial the panel offers **'Open settings'** (app settings
intent) and **'Try again'** to re-request permission. No camera is never a
dead end.

---

## Beat 4 — 2:45 · The cat detour

'Log a sighting' is ALWAYS reachable — pick either entry:

1. **Scan-catch:** point the scanner at a cat during a run → the Cat
   Distribution System card appears → confirm → the sticker lands in the Dex.
   **or** **App-bar route:** Home → **'Cat Dex'** tile → the Dex opens (after
   the Beat-1 reset: the Cat Level banner + 3 sticker cards) → tap the
   persistent app-bar **'Log a sighting'** action, top-right of the bar. On a
   truly empty Dex the shelf card's **'Log a sighting'** CTA opens the same
   flow instead — no empty-Dex precondition anywhere.
2. The flow is **photo → on-device analyse → sticker** (there are no
   species/notes fields): tap **'Choose from gallery'** → pick a photo → the
   on-device cat gate checks it → a cat cuts a sticker and the
   **'Added to the Dex'** panel offers **'View Cat Dex'**. No cat in the shot
   says **'No cat found in that photo. Try a clearer shot.'** — pick another
   photo, nothing breaks.
3. In the Dex, tap any sticker tile → sheet opens → tap
   **'Share sighting to board'** → SnackBar
   **'Sighting shared to the community board'** → the Community Board opens
   with the sighting as a resident-shared entry.

**Fallback (if the scan does not classify a cat):** the app-bar
**'Log a sighting'** action (and the empty-shelf CTA) reach the identical
photo → analyse → sticker flow; the detour never blocks the run-of-show.

---

## Beat 5 — 3:30 · The operator loop

1. Profile is the **app-bar avatar** (top-right, the resident's initial —
   NOT a bottom tab): tap it → **'Profile & settings'** → the
   **'Township staff'** card → flip the **'Staff mode'** switch ON (subtitle
   becomes **'On — operator dashboard available'**; turning it ON also jumps
   straight to the dashboard). **Keep Staff mode ON through Beat 6** — the
   **'Command center'** app-bar action only shows while staff is on.
2. The operator dashboard (**'Operator dashboard — Precinct 1'**) shows the
   stat row **Open / Triaged / Resolved** with the report cards below; the
   scope defaults to **'My precinct'** — tap **'All precincts'** for the whole
   queue. Queue reality after the Beat-1 reset: the seed already holds
   **2 submitted + 1 triaged** reports (plus your Beat-2 report →
   **3 open / 1 triaged / 1 resolved** on All precincts; **My precinct** shows
   2 open — the seed's 'Illegal dumping' report and yours). The new report is
   NOT the only open item. Card meta reads the shared labels —
   **Received / In review / Resolved** — never raw stored values.
3. On your Beat-2 report card (newest, on top) tap **'Triage'** → status chip
   becomes **Triaged**.
4. Then tap **'Mark resolved'** → the card moves down to
   **'Recently resolved'**.
5. Leave **Staff mode ON** (Beat 6 needs it): the Community Board / status
   list now shows **'Resolved: <category> — <precinct>'** for that incident.

**Fallback (if the Beat-2 card is not on top):** use the Open count as the
pointer — in 'My precinct' the open cards are the seed's 'Illegal dumping'
report plus yours; the newest one carries the tonal **'Triage'**.

---

## Beat 6 — 4:30 · The council view, then close

1. Home → tap the **'Command center'** app-bar icon (top-right shortcut;
   visible because Staff mode is still ON) → council tier opens. Narrate the
   panels:
   - **Resident scan mix (last scans)** — per-category counts computed live
     from the collection store (empty copy: 'No confirmed scans yet' until
     Beat 3's confirm lands).
   - **On-device vision parameters** — the truthful card listing
     **detector / input size / labels**: 'Primary detector: YOLO
     (yolo_detect_fp16, 640×640, COCO-80)', 'Fallback detector:
     EfficientDet-Lite0 int8, 320×320', MobileNet-v3 embedder + taught kNN,
     ML Kit label fallback — "what the card says is what the APK contains".
   - **Incidents (N open)** — tap one for the read-only drill-down
     (**Ref RP-######** + Received / In review / **Resolved** timeline, same
     data as the resident app).
   - **Situation report** — the disjoint triple: **'Hazard queue: X open,
     Y triaged, Z resolved'** (open counts submitted only — no figure
     double-counts triaged).
2. **Camera caveat:** leave the live camera preview with **in-app navigation**
   (bottom nav / on-screen back). **Hardware BACK from the live camera can
   crash the app** — a plugin-level teardown bug, documented in
   `demo_evidence/`; the demo never uses hardware back there.
3. Back to **Home**: point at **'My impact this month'** — points and impact
   counters now show the demo's totals.
4. Close the loop: Home → **'Demo data'** → **'Reset demo data'** → confirm
   **'Reset demo data'** → hand the phone over. The next demo starts from the
   **restored demo dataset**, on-device, offline.

**Fallback (if the command center is slow to fill):** the mix recomputes from
the store on every entry — leave and re-enter the screen; the incident
drill-down always matches the board, so narrate from either surface.

---

### Timing recap

| Beat | Clock | Surface | Anchor labels |
|------|-------|---------|---------------|
| 1 | 0:00 | Home → Demo data | 'Demo data' → 'Reset demo data' → 'Reset demo data?' → restored counts |
| 2 | 0:45 | Report form | 'Attach precinct' → 'Submit report' → 'Report logged — this is your receipt' (Ref RP-######) → 'Track my report' |
| 3 | 1:30 | Scan | explainer → 'Allow camera' / 'Import a photo' / 'Open settings' / 'Try again' |
| 4 | 2:45 | Cat Dex | app-bar 'Log a sighting' → 'Choose from gallery' → 'Share sighting to board' |
| 5 | 3:30 | App-bar avatar → Profile → Operator | 'Staff mode' (stay ON) → 'Triage' → 'Mark resolved' → 'Resolved: …' |
| 6 | 4:30–5:00 | Command center → Home | live scan mix · vision card (detector/input/labels) · drill-down → reset |

Total: 5:00. Hard stop rule: if any beat overruns, cut the Beat-4 detour
first, then the Beat-6 drill-down — the close (reset) always happens.
