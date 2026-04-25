import Testing
@testable import LingoPulseApp

@Suite struct ScopeTests {
    @Test func wildcardWireFormat() {
        #expect(Scope.wildcard.wireString == "*")
    }

    @Test func appScopeWireFormat() {
        #expect(Scope.app(.slack).wireString == "Slack")
    }

    @Test func fromWildcardWire() {
        #expect(Scope.from("*") == .wildcard)
    }

    @Test func fromAppWire() {
        #expect(Scope.from("Slack") == .app(.slack))
    }

    @Test func fromUnknownWire() {
        #expect(Scope.from("WeirdApp") == .app(.unknown))
    }
}
