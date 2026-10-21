import AppKit

enum NotchGeometry {
    /// The built-in display if it has a notch, otherwise the main screen.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    /// Size of the physical notch. Screens without one get a fake notch the height of the menu bar.
    static func notchSize(for screen: NSScreen) -> CGSize {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return CGSize(width: width, height: screen.safeAreaInsets.top)
        }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return CGSize(width: 190, height: max(24, menuBarHeight))
    }
}

enum Metrics {
    /// Width of each "wing" beside the notch in the compact live-activity state.
    static let wing: CGFloat = 38
    static let compactTopRadius: CGFloat = 6
    static let expandedTopRadius: CGFloat = 14
    static let expandedWidth: CGFloat = 620
    static let expandedContentHeight: CGFloat = 156
    /// Banner peeks: label font, icon column and the room the battery badge needs on the right.
    static let peekFontSize: CGFloat = 13
    static let peekIconWidth: CGFloat = 16
    static let peekIconSpacing: CGFloat = 5
    static let peekTrailingWidth: CGFloat = 70
    /// Transparent margin around the largest island so its shadow is not clipped.
    static let windowPadding: CGFloat = 40

    static func windowSize(notch: CGSize) -> CGSize {
        CGSize(width: max(expandedWidth, notch.width + 400) + windowPadding * 2,
               height: notch.height + expandedContentHeight + windowPadding)
    }
}
