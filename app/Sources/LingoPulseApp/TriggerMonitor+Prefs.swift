// Maps UserDefaults string pref values to TriggerMonitor enums and back.
// Round-trip guarantee: TriggerMonitor.SingleKey(prefValue: key.prefValue) == key (same for DoubleTapMod).
// Unknown strings fall back to defaults (.rightCommand / .shift).

extension TriggerMonitor.SingleKey {
    init(prefValue: String) {
        switch prefValue {
        case "rightOption": self = .rightOption
        case "fn":          self = .fn
        default:            self = .rightCommand
        }
    }

    var prefValue: String {
        switch self {
        case .rightCommand: return "rightCommand"
        case .rightOption:  return "rightOption"
        case .fn:           return "fn"
        }
    }
}

extension TriggerMonitor.DoubleTapMod {
    init(prefValue: String) {
        switch prefValue {
        case "off":     self = .off
        case "command": self = .command
        case "option":  self = .option
        default:        self = .shift
        }
    }

    var prefValue: String {
        switch self {
        case .off:     return "off"
        case .shift:   return "shift"
        case .command: return "command"
        case .option:  return "option"
        }
    }
}
