# Wrathspeed Contract Audit Log — Pass 2 (Aug 12, 2026)

## Closed in pass 2

### M3 — Anchored Health import
- `HealthImporting` protocol + `HealthImportResult` + `MockHealthImportService` moved to WrathspeedCore for DI/testing
- `LiveHealthImportService` uses `HKAnchoredObjectQuery`; anchor persisted via `HealthImportAnchorStore` only after merge + `persist()`
- `AnchoredHealthImportTests` (incremental anchor + UUID dedup)

### M4 — Plan calendar / undo / overlay
- N100 applied as reversible overlay via `PlanAdjustmentService.effectivePlan` (base plan no longer mutated in `TrainingPlanService.regenerate`)
- Undo via `PlanChange` + `applyNotFeeling100` / `endNotFeeling100`
- `WorkoutMoveDateSheet` (date picker move with override toggle)
- `ManagePlanView` (available days, frequency, long-run, diff preview, apply)
- Plan tab: Manage Plan entry, undo affordance, preflight before start

### M5 — Session durability
- `WorkoutPreflightView` (structure, location, watch/GPS summary)
- 12s Watch launch timeout UI (`WatchLaunchTimeoutView`: Retry / Start on Phone / Cancel)
- `SessionRecoveryView` on relaunch when snapshot exists (Save Partial / Discard)
- `SessionRecoveryTests`
- 3s countdown before primary session start (`ActiveSessionState.countdown`)

### M6 — Instant builder
- Structured instant builder with live preview + preflight gate
- Manual treadmill: distance steps require Next; time steps auto-advance; `WorkoutStepper.manualTreadmill`
- Instant workouts tagged `WorkoutSource.instant`; `record()` skips auto-completing planned workouts for instant source

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
- `HistoryEmptyStateUITests` added; onboarding UI test navigation steps updated

## Intentionally not implemented / risks

| Item | Status | Risk |
|------|--------|------|
| Local workout reminders | **Skipped** — no UserNotifications entitlement in `project.yml` | Users must rely on calendar habits until entitlement added |
| wger media | **Empty allowlist** — no fabricated IDs/URLs | Strength/mobility remain text + SF Symbol only |
| Treadmill actual-distance prompt at end | **Partial** — `applyActualTreadmillDistance` API exists; end-of-workout UI sheet not wired | Saved treadmill runs use speed×time estimate unless UI prompt added |
| Reduce Motion countdown | **Partial** — fixed 3s sleep; no `accessibilityReduceMotion` skip in session controller | Reduce Motion users still wait 3s |
| Health observer background delivery | **Partial** — anchored query on demand/import; no `HKObserverQuery` background path | Imports require app open / manual refresh |
| UI tests on iOS 26 | **Failing** — onboarding confirm step not reached in simulator (draft build timing/validation) | CI should investigate; unit tests pass |
| Pass 1 uncommitted user files | **Preserved** — not reset/discarded | `Theme/`, design handoff, etc. remain dirty/untracked |

## Test results (pass 2)

```
swift test --package-path WrathspeedCore
  → 39 tests (8 suites), 0 failures

xcodebuild -scheme Wrathspeed -destination 'generic/platform=iOS Simulator' build
  → BUILD SUCCEEDED

xcodebuild test -only-testing:WrathspeedTests (iOS 26.0, iPhone 17 Pro sim)
  → 23 tests, 0 failures

xcodebuild test -only-testing:WrathspeedUITests (iOS 26.0)
  → 2 tests, 2 failures (onboarding confirm not appearing within timeout)
```

## Pass 2 commits

See `git log` after pass 2 commit sequence (M3–M8 gap closure).
