import Foundation

enum AppKind: String, CaseIterable {
    case slack = "Slack"
    case discord = "Discord"
    case messages = "Messages"
    case mail = "Mail"
    case outlook = "Outlook"
    case linear = "Linear"
    case jira = "Jira"
    case confluence = "Confluence"
    case notion = "Notion"
    case cursor = "Cursor"
    case code = "Code"
    case visualStudioCode = "Visual Studio Code"
    case notes = "Notes"
    case googleChrome = "Google Chrome"
    case safari = "Safari"
    case arc = "Arc"
    case braveBrowser = "Brave Browser"
    case firefox = "Firefox"
    case iTerm2 = "iTerm2"
    case terminal = "Terminal"
    case alacritty = "Alacritty"
    case wezTerm = "WezTerm"
    case hyper = "Hyper"
    case warp = "Warp"
    case unknown = ""

    var isTerminal: Bool {
        switch self {
        case .iTerm2, .terminal, .alacritty, .wezTerm, .hyper, .warp: return true
        default: return false
        }
    }

    var defaultTone: Tone {
        switch self {
        case .slack, .discord, .messages: return .casual
        case .mail, .outlook, .linear, .jira, .confluence, .notion: return .professional
        case .cursor, .code, .visualStudioCode: return .technical  // simplification of "auto"
        default: return .neutral
        }
    }

    static func fromAppName(_ name: String) -> AppKind {
        AppKind(rawValue: name) ?? .unknown
    }
}

enum Tone: String, CaseIterable {
    case casual = "Casual"
    case neutral = "Neutral"
    case professional = "Professional"
    case technical = "Technical"
    case grammarOnly = "Grammar-only"
}

enum EditCategory: String, CaseIterable {
    case preposition
    case plural
    case calque
    case structure
    case typo
    case apostrophe
    case comparative
    case capitalization
    case grammar
    case other  // fallback for unknown wire values
}

enum Scope: Equatable {
    case wildcard
    case app(AppKind)

    var wireString: String {
        switch self {
        case .wildcard: return "*"
        case .app(let kind): return kind.rawValue
        }
    }

    static func from(_ wire: String) -> Scope {
        if wire == "*" { return .wildcard }
        let kind = AppKind.fromAppName(wire)
        return .app(kind)
    }
}

enum FeedbackReason: String, CaseIterable {
    case wrongMeaning = "wrong_meaning"
    case tooFormal = "too_formal"
    case tooCasual = "too_casual"
    case lostVoice = "lost_voice"
    case techTermChanged = "tech_term_changed"
    case toneMismatch = "tone_mismatch"
    case overSummarized = "over_summarized"
    case addedContent = "added_content"
    case other = "other"
}
