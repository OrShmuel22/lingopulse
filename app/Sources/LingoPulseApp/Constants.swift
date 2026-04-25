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
        static let axTrustPollSeconds: TimeInterval = 5.0
    }
    enum Layout {
        static let chipMinWidth: CGFloat = 280
        static let chipMinHeight: CGFloat = 70
        static let chipMaxWidth: CGFloat = 400
        static let chipMaxHeight: CGFloat = 200
        static let chipScreenMargin: CGFloat = 16
        static let chipElementOffset: CGFloat = 6
        static let chipSlideOffset: CGFloat = 8
    }
    enum Daemon {
        static let defaultURL = URL(string: "http://127.0.0.1:17823")!
        static let timeoutSeconds: TimeInterval = 60
    }
    enum Refine {
        static let minWordsForLiveTrigger: Int = 3
    }
}
