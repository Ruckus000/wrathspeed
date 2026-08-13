import Foundation

enum UITestingSupport {
    static let resetStoreLaunchArgument = "-uiTestingResetStore"

    /// True when UI tests pass `-uiTestingResetStore` in Debug builds only.
    static var shouldResetStore: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(resetStoreLaunchArgument)
        #else
        false
        #endif
    }
}
