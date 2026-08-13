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

## Phase A — Repository reconciliation (Aug 12, 2026)

Branch: `recovery/phase-a-repo-reconciliation` @ `76f253f`

### Reconciled
- Added 21 previously untracked source/resource files referenced by committed targets (Session helpers, Theme, fonts, `strength_catalog.json`, core reconcilers, UI-test harness).
- Moved `strength_catalog.json` from `WrathspeedCore` package resources to main app bundle; removed package `Resources` processing.
- `project.yml`: Design folder on iPhone/Watch/Widget targets, HealthKit entitlements properties, WrathspeedTests/WrathspeedUITests targets + scheme test entries.
- Regenerated Xcode project once via XcodeGen (pbxproj unchanged; xcscheme gained test build/testables).
- HealthKit entitlement present on iPhone (`Wrathspeed.entitlements`) and Watch (`WrathspeedWatch.entitlements`).

### Deliberately left dirty (user-owned / deferred)
- `WrathspeedWatch/WatchTodayView.swift`, `WrathspeedWatch/WrathspeedWatchApp.swift` (Watch UI/start-resolver redesign)
- `WrathspeedCore/Tests/WrathspeedCoreTests/PlanGeneratorTests.swift` (additional reconciler tests)
- `WrathspeedCore/Sources/WrathspeedCore/InstantWorkoutFactory.swift` (untracked; no committed references)
- `CURSOR_IMPLEMENTATION_PLAN.md`, `design_handoff_wrathspeed_ui/` (reference material)

### Clean-export acceptance gate (`git archive HEAD`)

```bash
EXPORT_DIR=$(mktemp -d) && git archive HEAD | tar -x -C "$EXPORT_DIR" && cd "$EXPORT_DIR"

swift test --package-path WrathspeedCore
# → 45 tests total: 11 XCTest + 34 Swift Testing (@Test), 0 failures

xcodebuild -project Wrathspeed.xcodeproj -scheme Wrathspeed \
  -destination 'generic/platform=iOS Simulator' build \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/wrathspeed-phase-a-derived
# → BUILD SUCCEEDED

xcodebuild -project Wrathspeed.xcodeproj -scheme Wrathspeed \
  -destination 'platform=iOS Simulator,id=C7B52543-2B29-4CE4-9AE6-1A79B9B05A9F' \
  test -only-testing:WrathspeedTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/wrathspeed-phase-a-derived
# → 23 tests, 0 failures

xcodebuild -project Wrathspeed.xcodeproj -scheme Wrathspeed \
  -destination 'platform=iOS Simulator,id=C7B52543-2B29-4CE4-9AE6-1A79B9B05A9F' \
  test -only-testing:WrathspeedUITests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/wrathspeed-phase-a-derived
# → 2 tests, 0 failures (HistoryEmptyStateUITests, OnboardingFlowUITests)
```

Simulator: iPhone 17 Pro, iOS 26.0 (`C7B52543-2B29-4CE4-9AE6-1A79B9B05A9F`)

### Compiler warnings (clean export build + tests)

Production / package source:
- `TrainingPlanService.swift:23` — variable `plan` was never mutated; consider `let`
- `SpeechCuePlayer.swift:43,45` — main actor-isolated UIKit/WatchKit haptics from nonisolated `playHaptic` (4 warnings)
- `MobilityPlayerView.swift:77-79` — main actor-isolated `remaining` / `advance()` from `Timer` Sendable closure (4 warnings)
- `StrengthPlayerView.swift:247` — `HKWorkout.init(activityType:start:end:)` deprecated in iOS 17

Unit tests:
- `OnboardingFlowTests.swift:10,35,67,77` — `var` never mutated; consider `let` (4 warnings)

UI tests:
- `HistoryEmptyStateUITests.swift`, `OnboardingFlowUITests.swift` — Swift 6 main actor isolation warnings on `XCUIApplication`/`XCUIElement` usage (expected in non-`@MainActor` test methods)

Tooling:
- `appintentsmetadataprocessor` — metadata extraction skipped (no AppIntents.framework dependency)

### Remaining blockers for Phase B
- Watch UI redesign (`WatchTodayView`, `WatchApp`) still only in dirty tree; committed Watch uses legacy list UI with `pendingStart` shim.
- `InstantWorkoutFactory.swift` untracked; not required for current build.
- Additional `PlanGeneratorTests` reconciler coverage only in dirty tree.
- HealthKit entitlement missing at **code-sign** time in simulator unit tests (logged at runtime; tests still pass with `CODE_SIGNING_ALLOWED=NO`).
