# Floating Tab Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the full-width text-only tab bar with a floating capsule that carries SF Symbols, takes no committed layout height, and does not scale with Dynamic Type.

**Architecture:** `MainTabView` stops stacking the bar in a `VStack` and mounts it as `.overlay(alignment: .bottom)`. A `\.wsBottomBarInset` environment value carries the bar's footprint down to `WSScreen`, the shared scroll container every tab root uses, so the last row still clears the bar. The bar stays chrome-class in the type ramp — it must not grow with text size, which is why Apple exempts tab bars.

**Tech Stack:** SwiftUI, iOS 26, Swift 6, XCTest + XCUITest, xcodegen.

Spec: `docs/superpowers/specs/2026-08-23-floating-tab-bar-design.md`

**Before you start:** `Design/` is compiled into the iOS app, the watch app and the widget extension. `WSTabBar` lives in `Wrathspeed/Theme/WSComponents.swift`, which is iOS-only — but run `xcodegen generate` after adding any file, then `git checkout -- Wrathspeed.xcodeproj/xcshareddata/xcschemes/Wrathspeed.xcscheme` (xcodegen and Xcode fight over the scheme; see the comment at the foot of `project.yml`).

**Test device:** iPhone 16e / iOS 26.0, UDID `476B8682-F582-48F2-834C-A5B9420E1188`. iPhone 16 simulators are below the deployment target and fail confusingly. Do not run a suite while another Xcode test session is live on the same device — concurrent runners produce "Restarting after unexpected exit" across unrelated suites.

---

### Task 1: Give `AppTab` its symbols

**Files:**
- Modify: `Wrathspeed/Theme/WSComponents.swift` (the `AppTab` enum)
- Test: `WrathspeedTests/WSTabBarTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `WrathspeedTests/WSTabBarTests.swift`:

```swift
import SwiftUI
import XCTest
@testable import Wrathspeed

final class WSTabBarTests: XCTestCase {
    // Inactive tabs render no visible text, so the label is the only thing carrying the tab's
    // name to VoiceOver and to the UI suites that navigate by tab name.
    func testEveryTabHasALabelAndASymbol() {
        for tab in AppTab.allCases {
            XCTAssertFalse(tab.label.isEmpty, "\(tab) has no label")
            XCTAssertFalse(tab.symbol.isEmpty, "\(tab) has no SF Symbol")
        }
    }

    func testSymbolsAreDistinct() {
        let symbols = AppTab.allCases.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count, "two tabs share a symbol")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project Wrathspeed.xcodeproj -scheme Wrathspeed -configuration Debug -destination "platform=iOS Simulator,id=476B8682-F582-48F2-834C-A5B9420E1188" -only-testing:WrathspeedTests/WSTabBarTests
```

Expected: compile failure, `value of type 'AppTab' has no member 'symbol'`.

- [ ] **Step 3: Add the property**

In `Wrathspeed/Theme/WSComponents.swift`, add to `AppTab` after `label`:

```swift
    var symbol: String {
        switch self {
        case .today: "bolt.fill"
        case .plan: "calendar"
        case .history: "chart.line.uptrend.xyaxis"
        case .settings: "slider.horizontal.3"
        }
    }
```

- [ ] **Step 4: Run it and watch it pass**

Same command as Step 2. Expected: `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add WrathspeedTests/WSTabBarTests.swift Wrathspeed/Theme/WSComponents.swift Wrathspeed.xcodeproj/project.pbxproj
git commit -m "Give each tab a symbol alongside its label"
```

---

### Task 2: The bottom-inset environment value

**Files:**
- Modify: `Wrathspeed/Theme/WSComponents.swift` (near `WSScreen`)
- Test: `WrathspeedTests/WSTabBarTests.swift`

`WSScreen` is used both by screens that sit under the bar and by screens that do not, so the clearance cannot be a constant.

- [ ] **Step 1: Write the failing test**

Append to `WrathspeedTests/WSTabBarTests.swift`:

```swift
    // A ScrollView is greedy and reports the height it was proposed, not its content, so the
    // clearance cannot be measured through WSScreen directly. This pins the arithmetic; the
    // proof that the clearance is actually enough is the end-of-scroll tap in
    // FloatingTabBarUITests, which is the only thing that really shows it.
    func testFootprintIsTheCapsulePlusItsGap() {
        XCTAssertEqual(WSTabBar.footprint, WSTabBar.height + WSTabBar.gap, accuracy: 0.001)
        XCTAssertGreaterThan(WSTabBar.footprint, 0)
    }

    func testTabHeightClearsTheFortyFourPointFloor() {
        XCTAssertGreaterThanOrEqual(WSTabBar.height, 44)
    }
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project Wrathspeed.xcodeproj -scheme Wrathspeed -configuration Debug -destination "platform=iOS Simulator,id=476B8682-F582-48F2-834C-A5B9420E1188" -only-testing:WrathspeedTests/WSTabBarTests
```

Expected: compile failure, no `wsBottomBarInset` and no `WSTabBar.footprint`.

- [ ] **Step 3: Add the environment value and the metrics**

In `Wrathspeed/Theme/WSComponents.swift`, immediately above `struct WSScreen`:

```swift
private struct WSBottomBarInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// How much room the floating tab bar needs at the bottom of a scroll view so its last row
    /// is not trapped underneath. Zero on screens with no bar over them.
    var wsBottomBarInset: CGFloat {
        get { self[WSBottomBarInsetKey.self] }
        set { self[WSBottomBarInsetKey.self] = newValue }
    }
}
```

- [ ] **Step 4: Have `WSScreen` consume it**

Replace the whole of `struct WSScreen` with:

```swift
struct WSScreen<Content: View>: View {
    var topPadding: CGFloat = 10
    @ViewBuilder var content: () -> Content

    @Environment(\.wsBottomBarInset) private var bottomBarInset

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.top, topPadding)
            .padding(.bottom, 28 + bottomBarInset)
        }
        .scrollIndicators(.hidden)
        .background(WSColor.bg.ignoresSafeArea())
    }
}
```

- [ ] **Step 5: Add the metrics to `WSTabBar`**

Add these two static properties inside `struct WSTabBar`, above `var body`:

```swift
    /// The capsule itself. Four tabs divide it, so this is also each tap target's height.
    static let height: CGFloat = 56
    /// How far it floats above the safe area.
    static let gap: CGFloat = 8
    /// What a scroll view underneath has to clear.
    static var footprint: CGFloat { height + gap }
```

- [ ] **Step 6: Run it and watch it pass**

Same command as Step 2. Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add Wrathspeed/Theme/WSComponents.swift WrathspeedTests/WSTabBarTests.swift
git commit -m "Carry the tab bar's footprint to scroll views in the environment"
```

---

### Task 3: Rebuild `WSTabBar` as a floating capsule

**Files:**
- Modify: `Wrathspeed/Theme/WSComponents.swift` (the whole `WSTabBar` body)

- [ ] **Step 1: Replace the body**

Keep the three static metrics from Task 2. Replace everything from `var body: some View {` to the closing brace of `struct WSTabBar` with:

```swift
    @Namespace private var activeTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = tab }
                } label: {
                    tabContent(tab)
                }
                .buttonStyle(.plain)
                // Inactive tabs show no text at all, so the name has to be declared. The UI
                // suites navigate by tab name and would otherwise lose three of four queries.
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
                // The bar deliberately does not grow with Dynamic Type -- Apple exempts tab bars
                // from the Larger Text criteria because a bar that scaled would take roughly a
                // quarter of the screen. Long-press shows the icon and the label at full size.
                .accessibilityShowsLargeContentViewer {
                    Label(tab.label, systemImage: tab.symbol)
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .background(WSColor.bgAlert, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(WSColor.hairlineStrong, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, Self.gap)
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        HStack(spacing: 7) {
            Image(systemName: tab.symbol)
                // Fixed, like the label: this is chrome, not content.
                .font(.system(size: 20, weight: .semibold))
                .accessibilityHidden(true)
            if isSelected {
                Text(tab.label)
                    .wsType(.chromeTab)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(isSelected ? WSColor.bg : WSColor.text50)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height - 12)
        .background {
            if isSelected {
                Capsule(style: .continuous)
                    .fill(WSColor.accent)
                    .matchedGeometryEffect(id: "activeTab", in: activeTab)
            }
        }
        .contentShape(Capsule(style: .continuous))
    }
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project Wrathspeed.xcodeproj -scheme Wrathspeed -configuration Debug -destination "platform=iOS Simulator,id=476B8682-F582-48F2-834C-A5B9420E1188"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the existing matrix test — the bar must still not grow**

```bash
xcodebuild test -project Wrathspeed.xcodeproj -scheme Wrathspeed -configuration Debug -destination "platform=iOS Simulator,id=476B8682-F582-48F2-834C-A5B9420E1188" -only-testing:WrathspeedTests/WSLayoutMatrixTests/testTabBarHeightIsIdenticalAtEveryTextSize
```

Expected: PASS. If it fails, something in the bar is scaling that should not be — check that the `Image` uses `.font(.system(size:))` and not an `.imageScale`.

- [ ] **Step 4: Commit**

```bash
git add Wrathspeed/Theme/WSComponents.swift
git commit -m "Rebuild the tab bar as a floating capsule with symbols"
```

---

### Task 4: Float the bar over the content

**Files:**
- Modify: `Wrathspeed/RootView.swift:86-105` (`MainTabView`)

- [ ] **Step 1: Replace `MainTabView`'s body**

```swift
    var body: some View {
        @Bindable var store = store
        Group {
            switch store.selectedTab {
            case .today: TodayView()
            case .plan: PlanView()
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // An overlay rather than a VStack row: in a stack the bar subtracted its full height
        // from every screen whether or not the screen needed it. Floating, content runs under
        // and beside it, and screens that end in a Spacer get the height back outright.
        .overlay(alignment: .bottom) {
            WSTabBar(selection: $store.selectedTab)
        }
        .environment(\.wsBottomBarInset, WSTabBar.footprint)
        .background(WSColor.bg.ignoresSafeArea())
    }
```

- [ ] **Step 2: Build and run the whole suite**

```bash
xcodebuild test -project Wrathspeed.xcodeproj -scheme Wrathspeed -configuration Debug -destination "platform=iOS Simulator,id=476B8682-F582-48F2-834C-A5B9420E1188"
```

Expected: `** TEST SUCCEEDED **`. The tab-name queries in `TapTargetUITests`, `Milestone4UITests` and `OnboardingFlowUITests` are the ones to watch — they pass only because Task 3 set explicit accessibility labels.

- [ ] **Step 3: Commit**

```bash
git add Wrathspeed/RootView.swift
git commit -m "Float the tab bar over content instead of stacking it"
```

---

### Task 5: Guard against content trapped under the bar

This is the failure mode a floating bar introduces, so it gets a test rather than an eyeball.

**Files:**
- Create: `WrathspeedUITests/FloatingTabBarUITests.swift`

- [ ] **Step 1: Write the test**

```swift
import XCTest

@MainActor
final class FloatingTabBarUITests: XCTestCase {
    // The bar floats over content now, so the risk is that a scroll view's last row ends up
    // underneath it and cannot be tapped. Scrolling to the end and hit-testing the last row is
    // the only thing that actually proves the clearance is right.
    func testLastRowOfEachTabClearsTheBar() {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        XCTAssertTrue(app.buttons["SETTINGS"].waitForExistence(timeout: 20))
        UITestOnboardingHelper.completeOnboarding(app)

        for tab in ["TODAY", "PLAN", "HISTORY", "SETTINGS"] {
            app.buttons[tab].tap()
            let scroll = app.scrollViews.firstMatch
            guard scroll.waitForExistence(timeout: 5) else { continue }
            for _ in 0 ..< 12 { scroll.swipeUp(velocity: .fast) }

            let bar = app.buttons["SETTINGS"].frame
            let candidates = (0 ..< app.buttons.count)
                .map { app.buttons.element(boundBy: $0) }
                .filter { $0.exists && $0.frame.height > 0 && $0.frame.minY < bar.minY }
            guard let lowest = candidates.max(by: { $0.frame.maxY < $1.frame.maxY }) else { continue }
            XCTAssertTrue(lowest.isHittable,
                          "\(tab): '\(lowest.label)' is under the floating bar and cannot be tapped")
        }
    }

    // The unit matrix can only measure the whole bar, so the per-tab hit region is asserted
    // here, where the frames are the real ones the system hit-tests against. An earlier draft
    // sized the tab content to a fixed 44pt inside a 56pt bar, which left a dead strip that
    // looked tappable and was not -- nothing in the unit tests could see it.
    func testEveryTabPresentsA44PointTarget() {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        XCTAssertTrue(app.buttons["TODAY"].waitForExistence(timeout: 20))
        UITestOnboardingHelper.completeOnboarding(app)

        for tab in ["TODAY", "PLAN", "HISTORY", "SETTINGS"] {
            let frame = app.buttons[tab].frame
            XCTAssertGreaterThanOrEqual(frame.height, 44, "\(tab) is only \(frame.height)pt tall")
            XCTAssertGreaterThanOrEqual(frame.width, 44, "\(tab) is only \(frame.width)pt wide")
        }
    }

    func testEveryTabIsReachableByName() {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        XCTAssertTrue(app.buttons["TODAY"].waitForExistence(timeout: 20))
        UITestOnboardingHelper.completeOnboarding(app)

        // Only the selected tab draws its label, so this fails the moment the inactive tabs
        // stop declaring their accessibility names.
        for tab in ["PLAN", "HISTORY", "SETTINGS", "TODAY"] {
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(tab) is not reachable by name")
            XCTAssertTrue(button.isHittable, "\(tab) is not hittable")
            button.tap()
        }
    }
}
```

- [ ] **Step 2: Regenerate the project so the new file is in the target**

```bash
xcodegen generate && git checkout -- Wrathspeed.xcodeproj/xcshareddata/xcschemes/Wrathspeed.xcscheme
```

- [ ] **Step 3: Run it**

```bash
xcodebuild test -project Wrathspeed.xcodeproj -scheme Wrathspeed -configuration Debug -destination "platform=iOS Simulator,id=476B8682-F582-48F2-834C-A5B9420E1188" -only-testing:WrathspeedUITests/FloatingTabBarUITests
```

Expected: PASS. A failure naming a row means `WSScreen`'s clearance is short — check that `MainTabView` publishes `WSTabBar.footprint` and that the failing screen actually uses `WSScreen`.

- [ ] **Step 4: Commit**

```bash
git add WrathspeedUITests/FloatingTabBarUITests.swift Wrathspeed.xcodeproj/project.pbxproj
git commit -m "Guard the floating bar against trapping content"
```

---

### Task 6: Add the tap-target measurement to the matrix

**Files:**
- Modify: `WrathspeedTests/WSLayoutMatrixTests.swift`

- [ ] **Step 1: Add the test**

Append inside `WSLayoutMatrixTests`, after `testTabBarHeightIsIdenticalAtEveryTextSize`:

```swift
    /// The bar does not scale, so its footprint has to be right at the default size and stay
    /// that way. Note this measures the *bar*, not the individual buttons -- a tab whose content
    /// is smaller than its cell would still pass here, so the real per-tab hit region is asserted
    /// in FloatingTabBarUITests.testEveryTabPresentsA44PointTarget.
    func testEachTabIsAtLeast44PointsAtEveryTextSize() {
        var selection = AppTab.today
        let binding = Binding(get: { selection }, set: { selection = $0 })
        for width in widths {
            for size in textSizes {
                let bar = measure(WSTabBar(selection: binding), width: width, size: size)
                XCTAssertGreaterThanOrEqual(WSTabBar.height, 44,
                                            "tab height is under the floor at \(width)pt / \(size)")
                XCTAssertGreaterThanOrEqual(bar.width / CGFloat(AppTab.allCases.count), 44,
                                            "tabs are narrower than 44pt at \(width)pt / \(size)")
            }
        }
    }
```

- [ ] **Step 2: Run the matrix**

```bash
xcodebuild test -project Wrathspeed.xcodeproj -scheme Wrathspeed -configuration Debug -destination "platform=iOS Simulator,id=476B8682-F582-48F2-834C-A5B9420E1188" -only-testing:WrathspeedTests/WSLayoutMatrixTests
```

Expected: `Executed 9 tests, with 0 failures`.

- [ ] **Step 3: Commit**

```bash
git add WrathspeedTests/WSLayoutMatrixTests.swift
git commit -m "Measure the floating bar's tap targets across the matrix"
```

---

### Task 7: Look at it

Two of the spec's risks are visual and cannot be asserted.

- [ ] **Step 1: Full suite plus the package**

```bash
xcodebuild test -project Wrathspeed.xcodeproj -scheme Wrathspeed -configuration Debug -destination "platform=iOS Simulator,id=476B8682-F582-48F2-834C-A5B9420E1188"
```

```bash
cd WrathspeedCore && swift test
```

Expected: `** TEST SUCCEEDED **` and `106 tests ... passed`.

- [ ] **Step 2: Screenshot all four tabs at the default text size**

```bash
xcrun simctl launch 476B8682-F582-48F2-834C-A5B9420E1188 com.wrathspeed.app -uiTestingResetStore -uiTesting -uiTestingSeedCompletedOnboarding
```

Then tap through the tabs and `xcrun simctl io 476B8682-F582-48F2-834C-A5B9420E1188 screenshot /tmp/tab-<name>.png` for each. Check specifically:

1. The bar reads clearly over each screen's content.
2. The strip of content visible in the 16pt margins beside the capsule does not look accidental — the spec calls out Plan's day rows and Today's week bar as the busiest cases.
3. The active capsule slides rather than jumping when tabs change.

- [ ] **Step 3: Screenshot at the largest accessibility size**

```bash
xcrun simctl launch 476B8682-F582-48F2-834C-A5B9420E1188 com.wrathspeed.app -uiTestingResetStore -uiTesting -uiTestingSeedCompletedOnboarding -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge
```

Note that this is a launch **argument** — as a launch environment variable it is silently inert, which is how the repo's Dynamic Type test passed at the default size for months. The bar must look identical to Step 2; that is the whole point of it being chrome.

- [ ] **Step 4: Confirm the large content viewer**

Set the simulator to an accessibility text size and long-press each tab. Expected: the system HUD shows the icon and the tab's name.

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "Tune the floating bar against the screens it sits over"
```

---

## Notes for whoever executes this

- **Do not** make the bar scale with Dynamic Type "for consistency" with the type ramp. It is chrome, it is exempt, and `testTabBarHeightIsIdenticalAtEveryTextSize` will fail if you try.
- **Do not** replace the explicit `.accessibilityLabel(tab.label)` with the visible text. Three of four tabs render no text, and several existing suites navigate by tab name.
- If a screen's last row still ends up under the bar, the fix is in `WSScreen`'s clearance or in that screen not using `WSScreen` — not in shrinking the bar.
