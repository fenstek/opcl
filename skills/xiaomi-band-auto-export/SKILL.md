---
name: xiaomi-band-auto-export
description: Set up automated daily health data export from Xiaomi Smart Band (via Zepp Life) on iPhone — no Mac required. Guides through Zepp Life → Apple Health sync, Health Auto Export configuration, iCloud Drive storage, and iOS Shortcuts automation. Use when a user wants to collect Xiaomi Band data automatically on iPhone and export it to CSV/JSON for analysis.
metadata:
  {
    "openclaw":
      {
        "emoji": "⌚",
      },
  }
---

# Xiaomi Band Auto-Export (iPhone, no Mac)

Automate daily health data collection from **Xiaomi Smart Band 7** via **Zepp Life** on iPhone.
Pipeline: `Zepp Life → Apple Health → CSV/JSON → iCloud Drive` — triggered every morning by iOS Shortcuts.

## Core rules

- Never modify Apple ID, iCloud account settings, or delete data without explicit user approval.
- Always confirm before recommending paid apps or subscriptions.
- Provide a rollback step after every major change.
- Do not claim iOS menu paths are exact — mark uncertain paths and offer 2 alternatives.
- Proceed step-by-step; confirm completion before moving to the next step.
- After each step, output a status: **✅ Done** or **⚠️ Action Required**.

---

## Step 0 — Collect prerequisites

Before starting, gather the following. Try to infer from context; only ask what is unknown.

1. iOS version (Settings → General → About → Software Version). Shortcuts automation without confirmation requires **iOS 15+**; recommended **iOS 16+**.
2. iCloud Drive enabled? (Settings → [your name] → iCloud → iCloud Drive).
3. Zepp Life version installed (App Store → profile icon → Purchased).
4. Target metrics (default set):
   - Steps
   - Sleep (stages if available)
   - Heart Rate (samples + resting)
   - SpO2
   - Workouts / Active Energy
5. Export time preference (default: **07:30 local time**).
6. Timezone confirmation (default: **Europe/Berlin**).

Present a numbered summary and ask the user to confirm or correct before proceeding.

---

## Step 1 — Zepp Life → Apple Health sync

### Enable Health permissions in Zepp Life

1. Open **Zepp Life** → tap profile icon (bottom-right) → **My devices** → select the band.
2. Go back to profile → **Health monitoring** (or **Settings** on older versions).
3. Tap **Connect to Apple Health** (or **HealthKit**).
4. iOS will show a permissions sheet — enable **all** categories, especially:
   - Steps, Walking + Running Distance
   - Heart Rate, Resting Heart Rate
   - Sleep Analysis
   - Blood Oxygen (SpO2)
   - Active Energy Burned
   - Workouts
5. Tap **Allow** (top-right).

**Alternate path if the option is missing:**
Settings app → Privacy & Security → Health → Zepp Life → enable all categories manually.

### Verify data is arriving

1. Open **Health app** → Browse tab → search for "Steps".
2. Tap Steps → scroll to Data Sources — confirm **Zepp Life** is listed.
3. Repeat for Heart Rate and Sleep Analysis.

**If no data appears after 10 minutes:**
- Force-quit Zepp Life, reopen it, and sync manually (pull down on the main screen).
- Check that the band is within Bluetooth range and the Zepp Life sync has completed (green checkmark).

**Rollback:** Settings → Privacy & Security → Health → Zepp Life → disable all categories.

---

## Step 2 — Choose and install a Health exporter

Present the following options and ask the user to choose before installing.

### Option A — Health Auto Export *(recommended)*
- **App:** Health Auto Export - CSV & XML (by Lybac)
- **Cost:** Free tier available; Pro unlock ~$4.99 one-time (required for automation).
- **Pros:** Purpose-built for this workflow; direct iCloud Drive support; background automation via Shortcuts; active development.
- **Cons:** Pro required for full automation; not fully free.
- **App Store search:** "Health Auto Export CSV"

### Option B — Shortcuts + Health (built-in, free)
- **Cost:** Free (uses only native iOS apps).
- **Pros:** No extra app needed; fully free.
- **Cons:** Export is XML only (Apple's native format), not CSV; requires manual parsing; less user-friendly for analysis.
- **Best for:** Users who will post-process data programmatically and want zero cost.

### Option C — QS Access
- **App:** QS Access (by Quantified Self Labs)
- **Cost:** Free.
- **Pros:** CSV export per metric; free.
- **Cons:** Manual trigger only (no true background automation); less polished.
- **App Store search:** "QS Access health"

**Default recommendation: Option A (Health Auto Export).**
Confirm with the user which option to proceed with, noting cost implications for Option A.

---

## Step 3 — Configure Health Auto Export (Option A)

*Skip this step if the user chose Option B or C.*

### Initial setup

1. Open **Health Auto Export**.
2. On first launch, tap **Get Started** → grant Health permissions (enable all relevant categories).
3. Tap **Export** tab (bottom nav).

### Configure export format

1. Tap **Format** → select **CSV** (one file per metric) or **Combined CSV** (all metrics in one file).
   Recommended: **CSV per metric** (easier to parse individually).
2. Tap **Date Range** → select **Last 1 Day** (for daily incremental exports).
   For first run, select **All Time** or a custom backfill range.

### Configure export destination

1. Tap **Destination** → **iCloud Drive**.
2. Navigate to (or create) the folder: `HealthExports/`.
   - If the folder does not exist: tap the folder-with-plus icon → name it `HealthExports`.
3. Tap **Select** to confirm.

### File naming

Set the filename template (if the app supports it) to include the date:
`health-{date}` → produces e.g. `health-2026-02-27-Steps.csv`

If no template option exists, the app uses its own naming convention — note what it uses for the automation step.

### Timezone

1. Tap **Settings** (gear icon) → **Timezone** → set to **Europe/Berlin**.

**Rollback:** Delete the app; revoke Health permissions via Settings → Privacy & Security → Health → Health Auto Export.

---

## Step 4 — iOS Shortcuts automation (daily trigger)

### Create the export Shortcut

1. Open **Shortcuts** app → tap **+** (top-right) → name it `Daily Health Export`.
2. Tap **Add Action** → search **Health Auto Export** → select **Export Health Data** (or similar action provided by the app).
   - If the app does not expose a Shortcuts action, use **Open App** action pointing to Health Auto Export; the app must support background export on launch.
3. Optionally add a **Show Notification** action: "Health export complete ✅".
4. Tap **Done**.

### Create the Automation (daily trigger)

1. In Shortcuts → **Automation** tab → tap **+** → **Personal Automation**.
2. Select **Time of Day** → set to **07:30** → **Daily**.
3. Tap **Next** → tap **Add Action** → search **Run Shortcut** → select `Daily Health Export`.
4. **Critical:** Toggle **Ask Before Running** → **OFF** (requires iOS 15+).
   - If the toggle is not available (older iOS), the automation will prompt daily — user must tap "Run" each morning.
5. Tap **Done**.

### Fallback if "Ask Before Running" cannot be disabled

The user will receive a notification each morning at 07:30. Tapping it runs the export. This is a one-tap manual step — inform the user and add it to the daily checklist.

**Rollback:** Shortcuts → Automation tab → swipe left on the automation → Delete.

---

## Step 5 — Option B setup: native XML export via Shortcuts (free path)

*Only follow this step if the user chose Option B.*

### Export Apple Health data natively

Apple Health can export all data as a ZIP archive (XML format):

1. Open **Health** app → tap profile photo (top-right) → **Export All Health Data**.
2. A `.zip` file is generated. iOS will ask where to save it.
3. In the share sheet, tap **Save to Files** → navigate to `iCloud Drive/HealthExports/`.

This is always a manual action in native iOS (no Shortcuts action exists for this in iOS ≤17).

**Automation workaround (iOS 16+):**
Use the **Shortcuts** `Export Health Samples` action (if available in your iOS version):
1. Add Action → search "Health" → look for **Export Health Samples**.
2. Configure the metric, date range, and output format.
3. Follow with a **Save File** action → iCloud Drive → `HealthExports/`.
4. Repeat for each metric or use multiple sequential Shortcut steps.
5. Wrap in a daily automation as described in Step 4.

Note: The availability of `Export Health Samples` varies by iOS version. Mark uncertain and verify on-device.

---

## Step 6 — First-run quality check

After setup, run the export manually once before relying on automation.

1. Open Shortcuts → find `Daily Health Export` → tap the play button (▶).
2. Wait 30–60 seconds.
3. Open **Files app** → iCloud Drive → `HealthExports/` → confirm a file was created today.
4. Open the file → verify:
   - [ ] Date column contains today's or recent dates.
   - [ ] No empty metric columns for expected data types.
   - [ ] Timestamps are in Europe/Berlin timezone (check UTC offset: `+01:00` winter, `+02:00` summer).
   - [ ] Steps > 0 for at least one recent day (sanity check).

### Produce a mini-report

After checking the file, output:

| Metric | Status | Notes |
|--------|--------|-------|
| Steps | ✅ / ⚠️ | |
| Sleep | ✅ / ⚠️ | Requires Zepp Life sleep tracking enabled |
| Heart Rate | ✅ / ⚠️ | |
| Resting Heart Rate | ✅ / ⚠️ | May populate overnight |
| SpO2 | ✅ / ⚠️ | Requires SpO2 monitoring enabled in band settings |
| Active Energy | ✅ / ⚠️ | |
| Workouts | ✅ / ⚠️ | Only present if workouts were recorded |

For any ⚠️ metric, explain the likely cause and how to enable it.

---

## Step 7 — Operations guide

Provide the user with the following reference block:

### What runs automatically
- Every day at 07:30: iOS Shortcuts triggers Health Auto Export → saves CSV to `iCloud Drive/HealthExports/`.

### What may require manual action
- If "Ask Before Running" could not be disabled: tap the morning notification to approve the export.
- After an iOS update: recheck that the Automation is still active (Shortcuts → Automation tab).
- If the band loses sync overnight: open Zepp Life manually → sync → re-run the Shortcut.

### How to verify today's export ran
1. Files app → iCloud Drive → `HealthExports/` → check the modification date of the latest file.
2. Or: open Health Auto Export → Export tab → check "Last Export" timestamp.

### How to restart if broken
1. Open Health Auto Export → run a manual export.
2. If that fails: revoke and re-grant Health permissions (Settings → Privacy & Security → Health → Health Auto Export → toggle all off, then back on).
3. If Shortcut automation is missing: recreate it following Step 4.
4. If Zepp Life data is missing in Health: re-enable Zepp Life Health permissions (Step 1).

---

## Step 8 — Full rollback

To completely undo all changes:

1. **Disable the Automation:**
   Shortcuts → Automation tab → swipe left on `Daily Health Export` → Delete.

2. **Delete the Daily Health Export Shortcut:**
   Shortcuts → My Shortcuts → long-press `Daily Health Export` → Delete.

3. **Revoke Health Export app permissions:**
   Settings → Privacy & Security → Health → [app name] → disable all categories.

4. **Uninstall the exporter app:**
   Long-press app icon → Remove App → Delete App. *(Confirm with user before doing this.)*

5. **Revoke Zepp Life Health permissions (optional):**
   Settings → Privacy & Security → Health → Zepp Life → disable all categories.

6. **Delete export files from iCloud Drive (optional):**
   Files app → iCloud Drive → `HealthExports/` → select files → Delete.
   *(Confirm with user before doing this — data is not recoverable from iCloud trash after 30 days.)*

---

## Final checklist

```
- [ ] Zepp Life writes to Apple Health (Steps, Heart Rate, Sleep visible in Health app)
- [ ] Health export app installed and configured (format: CSV, destination: iCloud Drive/HealthExports/)
- [ ] Daily automation enabled in Shortcuts (07:30, Ask Before Running: OFF if possible)
- [ ] Manual test run succeeded — file visible in iCloud Drive
- [ ] File contains data for recent dates with correct timezone (Europe/Berlin)
- [ ] Mini-report of available metrics produced
- [ ] Operations guide provided to user
- [ ] Rollback steps documented
```
