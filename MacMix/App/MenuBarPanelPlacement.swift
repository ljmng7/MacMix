import Foundation
import CoreGraphics

enum MenuBarPanelPlacement {
    static let menuBarGap: CGFloat = 4

    static func maximumHeight(anchor: CGRect?, visibleFrame: CGRect) -> CGFloat {
        let top = min(anchor?.minY ?? visibleFrame.maxY, visibleFrame.maxY) - menuBarGap
        return max(1, floor(top - visibleFrame.minY))
    }

    static func origin(panel: CGRect, anchor: CGRect, visibleFrame: CGRect) -> CGPoint? {
        guard panel.width > 0, panel.height > 0, anchor.width > 0,
              visibleFrame.width > 0, visibleFrame.height > 0,
              panel.height <= maximumHeight(anchor: anchor, visibleFrame: visibleFrame) + 0.5 else {
            // Let the viewport resize before moving a panel taller than the
            // available screen space. Never place its controls under the Dock.
            return nil
        }
        let lastX = max(visibleFrame.minX, visibleFrame.maxX - panel.width)
        let x = min(max(anchor.minX, visibleFrame.minX), lastX)
        let top = min(anchor.minY, visibleFrame.maxY) - menuBarGap
        return CGPoint(x: x.rounded(), y: (top - panel.height).rounded())
    }
}
