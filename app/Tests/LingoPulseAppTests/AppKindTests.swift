import Testing
@testable import LingoPulseApp

@Suite struct AppKindTests {
    @Test func terminalDetection() {
        #expect(AppKind.iTerm2.isTerminal == true)
        #expect(AppKind.terminal.isTerminal == true)
        #expect(AppKind.warp.isTerminal == true)
        #expect(AppKind.slack.isTerminal == false)
        #expect(AppKind.mail.isTerminal == false)
    }

    @Test func fromAppNameKnown() {
        #expect(AppKind.fromAppName("Slack") == .slack)
        #expect(AppKind.fromAppName("iTerm2") == .iTerm2)
        #expect(AppKind.fromAppName("Google Chrome") == .googleChrome)
    }

    @Test func fromAppNameUnknown() {
        #expect(AppKind.fromAppName("WeirdAppX") == .unknown)
    }

    @Test func defaultTone() {
        #expect(AppKind.slack.defaultTone == .casual)
        #expect(AppKind.mail.defaultTone == .professional)
        #expect(AppKind.cursor.defaultTone == .technical)
    }
}
