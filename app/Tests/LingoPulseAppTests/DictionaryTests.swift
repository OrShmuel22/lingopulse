import Testing
@testable import LingoPulseApp

@Suite("Dictionary")
struct DictionaryTests {

    @Test func detectHebrew_truePositives() {
        #expect(Dictionary.detectHebrew("שלום") == true)
        #expect(Dictionary.detectHebrew("hello") == false)
        #expect(Dictionary.detectHebrew("ה世界") == true)
    }

    @Test func buildPrompt_routes() {
        let heQuery = "משהו שמביע אושר"
        let enQuery = "something that expresses happiness"

        let hePromptResult = Dictionary.buildPrompt(query: heQuery)
        let enPromptResult = Dictionary.buildPrompt(query: enQuery)

        #expect(hePromptResult.contains("Hebrew speaker"))
        #expect(hePromptResult.contains("confidence"))
        #expect(enPromptResult.contains("precise English words from a description"))
        #expect(!enPromptResult.contains("confidence"))
    }

    @Test func parseResponse_validJsonArray() {
        let input = #"[{"word":"happy","example":"She looked happy.","register":"casual"}]"#
        let result = Dictionary.parseResponse(input)
        #expect(result.count == 1)
        #expect(result[0].word == "happy")
        #expect(result[0].register == "casual")
    }

    @Test func parseResponse_strippedMarkdownFences() {
        let input = "```json\n[{\"word\":\"x\",\"register\":\"casual\",\"example\":\"y\"}]\n```"
        let result = Dictionary.parseResponse(input)
        #expect(result.count == 1)
        #expect(result[0].word == "x")
    }

    @Test func parseResponse_regexFallback() {
        let input = #"some garbage text {"word":"x","register":"casual","example":"y"} more garbage"#
        let result = Dictionary.parseResponse(input)
        #expect(result.count == 1)
        #expect(result[0].word == "x")
    }

    @Test func parseResponse_emptyOnGarbage() {
        let result = Dictionary.parseResponse("hello world no json")
        #expect(result.isEmpty)
    }

    @Test func parseResponse_confidenceDefault() {
        let input = #"[{"word":"serene","example":"The lake was serene.","register":"formal"}]"#
        let result = Dictionary.parseResponse(input)
        #expect(result.count == 1)
        #expect(result[0].confidence == "high")
    }
}
