# Wrathspeed Contract Audit Log — Pass 2 (Aug 12, 2026)

## Closed in pass 2

### M3 — Anchored Health import
- `HealthImporting` protocol + `HealthImportResult` + `MockHealthImportService` moved to WrathspeedCore for DI/testing
- `LiveHealthImportService` uses `HKAnchoredObjectQuery`; anchor persisted via `HealthImportAnchorStore` only after merge + `persist()`
- `AnchoredHealthImportTests` (incremental anchor + UUID dedup)
- **Pass 2b:** Verified `Wrathspeed.entitlements` and `project.yml` contain HealthKit only — no `com.apple.developer.healthkit.background-delivery`. HKObserverQuery background path **not added** (would require new entitlement).

### M4 — Plan calendar / undo / overlay
- N100 applied as reversible overlay via `PlanAdjustmentService.effectivePlan` (base plan no longer mutated in `TrainingPlanService.regenerate`)
- Undo via `PlanChange` + `applyNotFeeling100` / `endNotFeeling100`
- `WorkoutMoveDateSheet` (date picker move with override toggle)
- `ManagePlanView` (available days, frequency, long-run, diff preview, apply)
- Plan tab: Manage Plan entry, undo affordance, preflight before start
- **Pass 2b:** Verified no UserNotifications usage description or entitlement in `project.yml` / entitlements — local workout reminders **not wired** (documented skip).

### M5 — Session durability
- `WorkoutPreflightView` (structure, location, watch/GPS summary)
- 12s Watch launch timeout UI (`WatchLaunchTimeoutView`: Retry / Start on Phone / Cancel)
- `SessionRecoveryView` on relaunch when snapshot exists (Save Partial / Discard)
- `SessionRecoveryTests`
- 3s countdown before primary session start (`ActiveSessionState.countdown`)
- **Pass 2b:** Reduce Motion skips countdown delay via `UIAccessibility.isReduceMotionEnabled` (instant start, preflight → recording path preserved)

### M6 — Instant builder
- Structured instant builder with live preview + preflight gate
- Manual treadmill: distance steps require Next; time steps auto-advance; `WorkoutStepper.manualTreadmill`
- Instant workouts tagged `WorkoutSource.instant`; `record()` skips auto-completing planned workouts for instant source
- **Pass 2b:** `TreadmillDistanceSheet` prompts for actual treadmill distance at end; calls `applyActualTreadmillDistance` before `record()`

### M7 — Strength / mobility / licenses
- Per-set strength logging (reps, load, skip/complete, rest timer, Finish Session)
- Local save via `StrengthSessionResult` independent of Health retry state
- `ContentLicensesView` + `ExerciseAboutView` (local/SF Symbol only; empty wger allowlist documented)
- Mobility player records `MobilitySessionResult`; history filters show strength/mobility results

### M8 — History / a11y
- `HistoryInsights` weekly + 4-week summaries wired in History recap card
- Designed empty states for runs/strength/mobility history
- Dynamic Type-relative custom fonts (`WSFont.* relativeTo:`)
- VoiceOver labels on core controls; 44pt targets on key actions
- `HistoryEmptyStateUITests` added
- **Pass 2b:** Onboarding UI tests fixed — default race date applied when DatePicker untouched; tests pass on iOS 26 (iPhone 17 Pro sim)

## Remaining risks

| Item | Status | Risk |
|------|--------|------|
| Local workout reminders | **Skipped** — no UserNotifications entitlement | Users must rely on calendar habits until entitlement added |
| wger media | **Empty allowlist** | Strength/mobility remain text + SF Symbol only |
| Health background observer | **Skipped** — no background-delivery entitlement | Incremental import runs on app open / manual refresh only |
| Watch timeout / mirrored session | **UI only on phone** | Requires real Watch hardware to fully verify |
| Treadmill target speed UI | **Partial** — speed defaults in session; no in-run speed picker | Users adjust speed on treadmill manually |

## Test results (pass 2b — Aug 12, 2026)

```bash
swift test --package-path WrathspeedCore
# → 39 tests (8 suites), 0 failures

xcodebuild -scheme Wrathspeed \
  -destination 'generic/platform=iOS Simulator' build \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/wrathspeed-derived
# → BUILD SUCCEEDED

xcodebuild -scheme Wrathspeed \
  -destination 'platform=iOS Simulator,id=C7B52543-2B29-4CE4-9AE6-1A79B9B05A9F' \
  test -only-testing:WrathspeedTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/wrathspeed-derived
# → 23 tests, 0 failures

xcodebuild -scheme Wrathspeed \
  -destination 'platform=iOS Simulator,id=C7B52543-2B29-4CE4-9AE6-1A79B9B05A9F' \
  test -only-testing:WrathspeedUITests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/wrathspeed-derived
# → 2 tests, 0 failures (OnboardingFlowUITests, HistoryEmptyStateUITests)
```

Simulator: iPhone 17 Pro, iOS 26.0 (`C7B52543-2B29-4CE4-9AE6-1A79B9B05A9F`)

## Pass 2 commits

```
(pass 2a — see git log 8667280..1d5351f)
(pass 2b — see git log after 1d5351f)
```

## Pass 2b commits

See `git log` after this update.
