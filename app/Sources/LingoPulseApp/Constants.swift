import Foundation
import CoreGraphics

enum Constants {
    enum Timing {
        static let debounceSeconds: TimeInterval = 1.5
        static let autoDismissSeconds: TimeInterval = 8.0
        static let chipShowAnimationSeconds: TimeInterval = 0.15
        static let chipHideAnimationSeconds: TimeInterval = 0.10
        static let keyGracePeriodSeconds: TimeInterval = 0.6
        static let coldStartThresholdSeconds: TimeInterval = 2.0
        static let notificationCooldownSeconds: TimeInterval = 60.0
        static let affirmationDismissSeconds: TimeInterval = 1.5
    }
    enum Layout {
        static let chipMinWidth: CGFloat = 280
        static let chipMinHeight: CGFloat = 70
        static let chipMaxWidth: CGFloat = 400
        static let chipMaxHeight: CGFloat = 200
        static let chipScreenMargin: CGFloat = 16
        static let chipElementOffset: CGFloat = 6
        static let chipSlideOffset: CGFloat = 8
        static let reviewPanelWidth: CGFloat = 540
        static let reviewPanelHeight: CGFloat = 400
    }
    enum Refine {
        static let minWordsForLiveTrigger: Int = 3
    }
    enum AppNames {
        static let quickRefine = "QuickRefine"
    }
}
