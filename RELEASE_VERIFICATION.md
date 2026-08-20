# Wrathspeed Release Verification

One-shot entry point: `CURSOR_MASTER_PROMPT.md`

Execution specification: `CURSOR_IMPLEMENTATION_PLAN.md`

Durable agent ledger: `CURSOR_EXECUTION_STATE.md`

Historical implementation evidence: `CONTRACT_AUDIT_LOG.md`

## RC correction v2 — software-correction gate — 2026-08-18

Prior Wave 4 signoff in this file is **invalidated**. This section is the independently rerun software-correction evidence. Passing Wave 4 tests did not override contradictory source; those defects were corrected and re-gated here.

**Verdict:** software-correction **PASS**. Signed release-candidate signoff is **not** claimed (physical iPhone/Watch, signing, TestFlight remain UNVERIFIED).

**Branch / HEAD:** `recovery/phase-a-repo-reconciliation` @ `9fdc057` plus **uncommitted** working tree (HEAD alone is not the implementation). Commits after `2c18b19`: `9a62233`, `787d460`, `530d912`, `6bfc5de`, `9fdc057`. Nothing staged this pass.

**Simulator:** iPhone 16e, iOS 26.0, UDID `476B8682-F582-48F2-834C-A5B9420E1188`

**Xcode:** 26.6 (17F113), iOS SDK 26.5

| # | Gate | DerivedData | Result |
|---|---|---|---|
| 1 | `git diff --check 2c18b19` + required untracked whitespace/conflict scan | n/a | **PASS** |
| 2 | `swift test --package-path WrathspeedCore` | SPM default | **PASS** — 52 XCTest + 90 Swift Testing = 142, 0 failures (~1.3s) |
| 3 | WrathspeedTests | `/tmp/wrathspeed-rc-v2-unit-derived-2` | **PASS** — 153 tests, 0 failures (19s wall) |
| 4 | WrathspeedUITests (6, serialized) | `/tmp/wrathspeed-rc-v2-uitest-derived-3` | **PASS** — 6 tests, 0 failures (263s wall / 245.483s test) |
| 5 | Clean Debug simulator build | `/tmp/wrathspeed-rc-v2-debug-derived-b` | **PASS** (14s) |
| 6 | Clean Release simulator build | `/tmp/wrathspeed-rc-v2-release-derived` | **PASS** (32s) |
| 7 | Warning scan of saved logs | those paths | **PASS** — repository-source `*.swift:*: warning:` = 0. Toolchain: `appintentsmetadataprocessor` “Metadata extraction skipped. No AppIntents.framework dependency found.” |
| 8 | Release `nm` + `strings` | Release `.app/Wrathspeed` | **PASS** — no DEBUG UITest/launch-arg seams |
| 9 | Factory / project membership | Package.swift + pbxproj | **PASS** — `InstantWorkoutFactory.swift` not compiled |
| 10 | Effective diff `2c18b19` → working tree | n/a | Inspected |

UI smoke (6): GuidedResume (41.534s), HistoryEmptyState (24.128s), Milestone4 Dynamic Type (25.793s) + Manage Plan (35.857s), OnboardingFlow (22.811s), PreflightLiveStart (95.361s).

Test budget unchanged: **14 / 15** new unit functions (existing tests extended; last slot unused), **2 / 2** UI smokes, **6** UI tests max.

### Post-review Health route correction — 2026-08-18

- Replaced the callback/unstructured-task route accumulator with `HKWorkoutRouteQueryDescriptor`'s ordered async sequence.
- Route-query failures now degrade only the optional route evidence instead of leaving the entire Health import suspended.
- Re-ran WrathspeedCore: **52 XCTest + 90 Swift Testing = 142, 0 failures**.
- Re-ran WrathspeedTests: **153, 0 failures** (`/tmp/wrathspeed-route-fix-unit`).
- Clean Release simulator build: **PASS** (`/tmp/wrathspeed-route-fix-release`).
- UI smokes were not rerun because this correction changes only the live HealthKit adapter; the saved RC UI result remains **6 / 6**.
- Deferred, non-blocking follow-up: consider bounded re-enrichment when HealthKit associates or updates a route after its workout has already been anchored.

## Automated baseline — 2026-08-18 (pre–Wave 3/4)

- WrathspeedCore: 46 XCTest + 88 Swift Testing checks passed.
- Wrathspeed app unit tests: 147 passed.
- Wrathspeed UI smoke tests: 4 passed on iPhone 16e, iOS 26.0.
- Generic Release iOS Simulator build succeeded, including Watch and widget compilation.
- Wave 0 (2026-08-18): production warning categories fixed; Debug/Release builds warning-free for Swift sources. Evidence in `CURSOR_EXECUTION_STATE.md`.

## Wave 4 release-candidate gate — 2026-08-18

**Branch / HEAD:** `recovery/phase-a-repo-reconciliation` @ `9fdc057` (Lane A cherry-picks `6bfc5de` + `9fdc057`; all Wave 2–4 coordinator wiring **uncommitted**)

**Simulator:** iPhone 16e, iOS 26.0, UDID `476B8682-F582-48F2-834C-A5B9420E1188` (Booted)

**DerivedData isolation:** UI smokes `/tmp/wrathspeed-wave3-uitests-derived`; Wave 4 unit/build `/tmp/wrathspeed-wave4-derived`. Xcode jobs run **serialized** (no concurrent simulator builds/tests).

| # | Gate | Command | Result |
|---|---|---|---|
| 1 | Whitespace | `git diff --check` | **PASS** — no conflict markers or whitespace errors |
| 2 | Core tests | `swift test --package-path WrathspeedCore` | **PASS** — 90 tests in 15 suites, 0 failures |
| 3 | App unit tests | `xcodebuild test -project Wrathspeed.xcodeproj -scheme Wrathspeed -destination 'platform=iOS Simulator,id=476B8682-F582-48F2-834C-A5B9420E1188' -derivedDataPath /tmp/wrathspeed-wave4-derived -only-testing:WrathspeedTests -parallel-testing-enabled NO` | **PASS** — 153 tests, 0 failures |
| 4 | UI smoke suite (6) | `xcodebuild test … -derivedDataPath /tmp/wrathspeed-wave3-uitests-derived -only-testing:WrathspeedUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1` | **PASS** — 6 tests, 0 failures (~244 s) |
| 5 | Clean Debug build | `xcodebuild clean build -project Wrathspeed.xcodeproj -scheme Wrathspeed -configuration Debug -destination 'platform=iOS Simulator,id=476B8682-F582-48F2-834C-A5B9420E1188' -derivedDataPath /tmp/wrathspeed-wave4-derived CODE_SIGNING_ALLOWED=NO` | **PASS** |
| 6 | Clean Release build | `xcodebuild clean build … -configuration Release …` (same flags) | **PASS** |
| 7 | Release seam audit | `nm` + `strings` on `/tmp/wrathspeed-wave4-derived/Build/Products/Release-iphonesimulator/Wrathspeed.app/Wrathspeed` | **PASS** — 0 matches for `setForceSaveFailureForTesting`, `forceSaveFailure`, `testing_handleWorkoutResult`, `watchPublicationCountForTesting`, `shouldResetStore`, `UITestingSupport`, `shouldSimulateLiveRecording`, `shouldPresentMobilityPreRun`, `shouldSeedInProgressMobility`, `seedInProgressMobilityForUITesting`, `beginSimulatedLiveRecording`, `finishSimulatedLiveRecording`, and launch-arg strings `uiTestingResetStore`, `uiTestingSimulateLiveRecording`, `uiTestingPresentMobilityPreRun`, `uiTestingSeedInProgressMobility` |

### UI smoke suite (6 tests)

| Test | File | Notes |
|---|---|---|
| `testOnboardingPreviewAndConfirmationReachMainTabs` | `OnboardingFlowUITests` | Shared `UITestOnboardingHelper` |
| `testHistoryShowsEmptyRunsStateAfterOnboarding` | `HistoryEmptyStateUITests` | Shared helper |
| `testWeeklyCalendarAndManagePlanFlows` | `Milestone4UITests` | Shared helper |
| `testDynamicTypeKeepsPlanActionsReachable` | `Milestone4UITests` | Shared helper |
| `testPreflightOutdoorAndTreadmillReachLiveRun` | `PreflightLiveStartUITests` | **New** — uses `-uiTestingSimulateLiveRecording` (DEBUG live-run seam; no HealthKit on simulator) |
| `testMobilitySessionResumesAfterRelaunch` | `GuidedResumeUITests` | **New** — uses `-uiTestingPresentMobilityPreRun` (DEBUG; XCTest row tap unreliable under ScrollView + presentation stack); verifies partial progress (`2 / 3`) survives terminate + relaunch without `-uiTestingResetStore` |

**Out of automated UI scope (by design):** GPS backgrounding, Health authorization UI, WatchConnectivity, haptics, audio, signed migration.

### Test budget

| Bucket | Used | Limit | Notes |
|---|---|---|---|
| New unit test functions (lanes A/B/C) | **14** | **15** | Lane D + Wave 3 added **0** unit tests |
| New UI smoke tests | **2** | **2** | Preflight→live, guided resume |
| UI suite size | **6** | **6** max | |

### Failure-path trace (code + tests — not physical device)

| Path | UI → persistence trace | Evidence |
|---|---|---|
| Location denied | Preflight shows GPS status; outdoor run can proceed degraded; live session does not require route for local save | `WorkoutPreflightView`, `WorkoutSessionController`, `CoachingMVPHardeningTests` |
| Health authorization / save / import failure | Local `WorkoutResult` / guided results persist first; `healthSync.state == .failed` retained; import errors on `healthImportErrorMessage` (not global `errorMessage`); retry via History/status card | `AppStore`, `WorkoutSessionController.end`, `HealthImportPersistenceTests`, `GuidedSessionPersistenceTests.testStrengthHealthFailurePreservesCompletedLocalResult` |
| Optional Health detail missing | `HealthImportMerge.markUnavailable` marks enrichment absent without deleting local history | `HealthImport.swift`, `HealthImportTests` |
| Duplicate / delayed Health and Watch results | `WorkoutResultMerge` identity keys; watch start resolver duplicate-safe | `WorkoutResultMergeTests`, `CoachingMVPHardeningTests.testWatchStartResolverHandlesEitherArrivalOrderAndDuplicates`, `WorkoutResultRecordTests.testSavePartialDoesNotCreateDuplicateForCompletedWorkout` |
| Treadmill final-distance correction | `TreadmillDistanceSheet` + `WorkoutResultTreadmillTests` (confirmed distance once, retry after failure) | `RootView`, `WorkoutResultTreadmillTests` |
| Interrupted guided session | Players `persistProgress` → `recordMobilityResult` / strength equivalent with `lifecycle: .inProgress` + progress | `MobilityPlayerView`, `GuidedSessionPersistenceTests.testMobilityPartialResumeAndComplete` |
| Relaunch / resume | `GuidedSessionPolicy.inProgressMobility` restores movement index; Today RESUME label; UITest relaunch without reset | `TodayView`, `GuidedResumeUITests`, `GuidedSessionPersistenceTests` |

### Diff / integration review

- **No unrelated refactors** beyond coordinator-owned presentation, History, and Lane A–C integration scope.
- **Single instant-workout SoT:** `InstantWorkoutBuilder.swift` compiled; `InstantWorkoutFactory.swift` untracked and **absent** from `project.yml`.
- **User-owned untracked preserved:** `.serena/`, `design_handoff_wrathspeed_ui/`, `CURSOR_IMPLEMENTATION_PLAN.md`, `CURSOR_MASTER_PROMPT.md`, `InstantWorkoutFactory.swift` — not staged.
- **Migration:** guided lifecycle defaults (`missing → completed`) in domain; no unsafe silent deletion.
- **Units:** distances in metres at persistence boundaries; `WSFormat` locale display only.
- **Privacy / entitlements:** no new entitlements in this wiring pass; physical entitlement audit still **UNVERIFIED**.
- **Coordinator fixes during Wave 3 UITests:** `mobility_catalog.json` transition/rest seconds (catalog load); Today `GuidedPlayer` single `fullScreenCover` (strength + mobility); skip Health primer on `-uiTestingResetStore` fresh launches; DEBUG UITest seams (`simulateLiveRecording`, `presentMobilityPreRun`, optional `seedInProgressMobility`).

## Required before release-candidate signoff

- [x] Wave 0: repository convergence, reproducible baseline, warning-free builds
- [x] Lane A: run preflight/end/treadmill and truthful instant workouts (simulator + unit evidence)
- [x] Lane B: Health evidence, deletions, and recovery contract (unit/core evidence)
- [x] Lane C: resumable local guided sessions
- [x] Wave 2: integrated core/app/Release gates (reconfirmed Wave 4)
- [x] Lane D: History, recovery UI, and accessibility closure (coordinator integration; 0 new unit tests)
- [x] Wave 3: UI smoke suite (6) + onboarding helper consolidation
- [x] Wave 4: clean automated release-candidate verification (**invalidated** by RC correction v2 source review; superseded by the RC correction v2 section above)
- [x] RC correction v2: software-correction gates rerun 2026-08-18 (this file, top section)
- [ ] Signed physical-device verification (**UNVERIFIED** — simulator cannot substitute)

## Physical iPhone — UNVERIFIED

- [ ] Phone-only outdoor run with GPS route and locked/background phone
- [ ] Live Activity uses selected units and ends correctly
- [ ] Pause/resume, audio cues, confirmed end
- [ ] Location denial degrades without losing the workout
- [ ] Health save failure retains local result and exposes retry
- [ ] Manual treadmill target, step advance, actual-distance confirmation
- [ ] External Health import, enrichment, deduplication, manual match/unmatch
- [ ] Miles and kilometres end-to-end

## Physical Apple Watch — UNVERIFIED

- [ ] Watch-only start/finish
- [ ] Phone-started mirrored Watch session
- [ ] 12-second Retry / Start on Phone / Cancel
- [ ] Phone End stops Watch primary once
- [ ] Disconnect/reconnect during workout
- [ ] Lost Watch transfer recovered through Health exactly once
- [ ] Late mirror after phone fallback rejected safely
- [ ] Cancel/restart and finish/immediate-restart leave no orphan
- [ ] Units, steps, haptics, and audio cues agree with iPhone

## Upgrade, privacy, and accessibility — partial

- [x] Fresh install and onboarding draft/confirmation (UI smoke + unit tests)
- [ ] Signed upgrade from populated legacy data with no loss/duplication (**UNVERIFIED** — needs signed device)
- [x] Relaunch after completed, failed-Health, and recoverable sessions (unit + `GuidedResumeUITests`)
- [ ] Accessibility Inspector on core journeys (**UNVERIFIED** manual)
- [ ] VoiceOver: onboarding, preflight, live controls, History, guided sessions (**UNVERIFIED** manual)
- [x] Dynamic Type: default, XXXL (`Milestone4UITests.testDynamicTypeKeepsPlanActionsReachable`)
- [ ] Reduce Motion physical/manual observation (**UNVERIFIED**). Code: iOS countdown skip via `UIAccessibility.isReduceMotionEnabled`; History split bars use `@Environment(\.accessibilityReduceMotion)`; CelebrationView has no custom animation.
- [ ] Entitlements, permission copy, privacy manifest, background modes (**UNVERIFIED** manual audit)
- [ ] Redacted diagnostics contain no route coordinates, Health samples, or recent results (**UNVERIFIED**)
- [ ] Content licenses accurately state local fallback/empty verified media allowlist (**UNVERIFIED**)

## Signoff record

| Field | Value |
|---|---|
| Integration commit | **None this pass** — existing commits `9a62233`…`9fdc057` plus large uncommitted working tree on `recovery/phase-a-repo-reconciliation` @ `9fdc057` |
| App build number | Not bumped (uncommitted) |
| Devices / OS | Simulator only: iPhone 16e, iOS 26.0 |
| Automated gate date | 2026-08-18 (RC correction v2) |
| Failures | None in software-correction gates |
| Accepted limitations | Physical Health/Watch/GPS/VoiceOver/Reduce Motion UNVERIFIED; DEBUG UITest seams Debug-only; first-launch mobility present arg is setup-only |
