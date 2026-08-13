# Wrathspeed Release Verification Notes

## Automated coverage in CI / simulator
- WrathspeedCore unit tests (plan, adaptation, health import, onboarding validation, migration)
- Wrathspeed app unit tests (persistence migration, onboarding flow, harness)
- Onboarding UI test (preview + confirm path)
- Generic iOS Simulator build (iPhone app, Watch target, widget extension)

## Still requires real hardware (unverified in this environment)
- Phone-only outdoor run with GPS lock/background route
- Watch-only start and mirrored session
- 12s Watch timeout retry / start-on-phone / cancel flow
- Live Activity on lock screen with selected units
- Lost Watch workout recovered via Health import on phone
- Denied location during outdoor run (degraded mode)
- Health save failure with local result retained + retry
- Accessibility Inspector pass on core workout controls
- Reduce Motion countdown alternative
- Bluetooth disconnect mid-run

## Privacy / permissions review
- Health read/write limited to workout, heart rate, energy, route types used
- Location requested only for outdoor recording
- No production logging of route coordinates, HR samples, or recent race results
- Diagnostics export is user-triggered and redacted (counts/status only)

## Fresh install / migration
1. Install app → onboarding draft/confirm → versioned records created
2. Relaunch → no duplicate migration
3. Legacy snapshot users → one-shot migration with legacy blob retained
