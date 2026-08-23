# Floating tab bar

Date: 2026-08-23

## Problem

The tab bar takes about 100pt of an 844pt screen — roughly 12% — and it takes it permanently,
because `RootView` stacks it under the content in a `VStack` rather than over it. Of that height,
44pt is the label row, 22pt is hand-rolled bottom padding, and 34pt is the home-indicator safe
area. The 22pt is waste: it pads for a home indicator the safe area already accounts for.

It is also text-only, which the design handoff specified deliberately — *"no images, icons or SF
Symbols in the redesign"* and, for the tab bar, *"No icons."* In use it reads flat and generic.

This spec overrides that part of the handoff. Everything else in the handoff stands.

## Decisions

| Decision | Choice | Why |
| --- | --- | --- |
| Structure | Floating bar over content | Reclaims committed layout height; content passes under and beside it |
| Icons | SF Symbols | Scale, localise and stay legible for free; no drawing or maintenance |
| Treatment | Rounded capsule, filled active tab | Clearest active state; strongest read of the three mocked |
| Scroll behaviour | Always visible | Predictable; a moving target costs more than the space it saves |

### What the space saving actually is

Worth stating precisely, because "floating" oversells it. Screens that do not fill their height —
Today, which ends in a `Spacer` — get back the full ~66pt. Scrolling screens still need their last
row to clear the bar, so they trade committed height for bottom padding and end up roughly level at
the bottom of the scroll; their gain is that content runs *under and beside* a floating capsule
rather than stopping at a full-width wall. The 22pt of redundant padding is reclaimed everywhere.

## Design

### Structure

`RootView` drops the `VStack`. Content fills the window and the bar mounts as
`.overlay(alignment: .bottom)`, inset 16pt on each side and floating 8pt above the safe area.

Scroll containers need clearance so the last row is not trapped under the bar. Every tab root
(`TodayView`, `PlanView`, `HistoryView`, `SettingsView`) and every screen pushed beneath them
already routes through `WSScreen`, so this is one change in one component — but `WSScreen` is also
used by screens with no bar over them, so the inset cannot be hardcoded.

A `\.wsBottomBarInset` environment value carries it: default `0`, set by `RootView` to the bar's
height plus its gap (56 + 8 = 64pt), which `WSScreen` adds to its existing 28pt bottom padding.
Environment propagation gives pushed screens the inset automatically, since the overlay sits above
them too.

No reset is needed for the screens that cover the bar. The celebration, live run, players and
recovery screens are all presented as `fullScreenCover` from `RootView`, so they render above the
overlay, and none of them uses `WSScreen` — so none consumes the inset. If one ever does, it should
set the inset to `0`.

### The bar

- Capsule, 56pt tall, `WSColor.bgAlert` fill, `WSColor.hairlineStrong` hairline border.
- Four tabs divide the width, so each tap target is 56pt tall — past the 44pt floor with room.
- **Active**: accent-filled capsule containing the symbol and the label, inked `WSColor.bg`.
- **Inactive**: symbol only, `WSColor.text50` — lifted from today's `text35`, which was tuned for
  the app background and reads too faint on the bar's lighter field.
- Symbols: `bolt.fill` (Today), `calendar` (Plan), `chart.line.uptrend.xyaxis` (History),
  `slider.horizontal.3` (Settings), fixed at 20pt.
- The active capsule slides between tabs with `matchedGeometryEffect`.

### Dynamic Type

Unchanged from the type system that landed in `3952d2e`, and the reason it holds: the bar is
chrome-class and does not scale. That is precisely why Apple exempts tab bars from the Larger Text
criteria — a bar that scaled would take a quarter of the screen. Icons are fixed for the same
reason.

Long-press shows `Label(tab.label, systemImage: tab.symbol)` in the Large Content Viewer — icon and
text together at full size, which is what that API is for and an improvement on the text-only
version currently shipped.

### Accessibility

Inactive tabs render no visible text, so their names must be declared rather than inferred:

- Each tab is a `Button` with an explicit `.accessibilityLabel(tab.label)`.
- The active tab carries `.isSelected`.
- Symbols are decorative — `.accessibilityHidden(true)` — with the label carrying the meaning.

`TapTargetUITests` already taps `app.buttons["TODAY"]`, and `Milestone4UITests`,
`OnboardingFlowUITests` and others navigate by tab name. Explicit labels keep every one of those
queries working; without them, three inactive tabs would lose their names.

## Files

- `Wrathspeed/Theme/WSComponents.swift` — rewrite `WSTabBar`; add `symbol` to `AppTab`; add the
  bottom-inset environment value; `WSScreen` consumes it.
- `Wrathspeed/RootView.swift` — `VStack` becomes content plus `.overlay(alignment: .bottom)`, and
  publishes the inset.

## Testing

- `WSLayoutMatrixTests.testTabBarHeightIsIdenticalAtEveryTextSize` applies unchanged — the bar is
  still chrome and still must not grow.
- New measurement: each tab is ≥44pt at every text size.
- New UI test: for each tab root, scroll to the end and tap the last row. Trapping content under a
  floating bar is the failure this design introduces, so it gets an explicit guard rather than a
  visual check.
- The existing suite must stay green, particularly the tab-name queries in `TapTargetUITests`,
  `Milestone4UITests` and `OnboardingFlowUITests`.

## Out of scope

- Hide-on-scroll. Considered and rejected: a moving target costs more than the space it saves.
- Custom angular icons drawn from `WSMarkGeometry`. Mocked and set aside in favour of SF Symbols;
  revisit if the bar still reads generic once built.
- The rest of the handoff's no-icons rule. Only the tab bar is exempted here.

## Risks

- **Content trapped under the bar.** The reason the inset is an environment value rather than a
  constant, and the reason the end-of-scroll tap is a test rather than an eyeball.
- **Content reading badly beside the bar.** The capsule is inset 16pt per side, so content now
  shows in the margins beside it and continues under it as you scroll. The fill is opaque so the
  bar itself stays legible, but the strip of content visible around it needs a look on the busiest
  screens — Plan's day rows and Today's week bar — rather than being assumed fine.
