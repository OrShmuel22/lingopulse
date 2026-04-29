import Testing
import Foundation
@testable import LingoPulseApp

@Suite struct PreviewDiffTests {
    @Test func identicalStringsHaveOneSameSegment() {
        let segs = PreviewDiff.compute(original: "hello world", refined: "hello world")
        #expect(segs.count == 1)
        #expect(segs.first?.kind == .same)
        #expect(segs.first?.text == "hello world")
    }

    @Test func wordReplacementShowsAddedAndRemoved() {
        let segs = PreviewDiff.compute(original: "i are going", refined: "I am going")
        let kinds = segs.map(\.kind)
        #expect(kinds.contains(.added))
        #expect(kinds.contains(.removed))
        // Reconstructed original = same + removed pieces (in original order)
        let reconstructedOriginal = segs.filter { $0.kind != .added }.map(\.text).joined()
        #expect(reconstructedOriginal == "i are going")
        let reconstructedRefined = segs.filter { $0.kind != .removed }.map(\.text).joined()
        #expect(reconstructedRefined == "I am going")
    }

    @Test func insertionOnlyHasNoRemovedSegments() {
        let segs = PreviewDiff.compute(original: "hello", refined: "hello world")
        #expect(!segs.contains(where: { $0.kind == .removed }))
        let reconstructed = segs.filter { $0.kind != .removed }.map(\.text).joined()
        #expect(reconstructed == "hello world")
    }

    @Test func deletionOnlyHasNoAddedSegments() {
        let segs = PreviewDiff.compute(original: "hello world", refined: "hello")
        #expect(!segs.contains(where: { $0.kind == .added }))
        let reconstructed = segs.filter { $0.kind != .added }.map(\.text).joined()
        #expect(reconstructed == "hello world")
    }

    @Test func emptyOriginalIsAllAdded() {
        let segs = PreviewDiff.compute(original: "", refined: "new content")
        for seg in segs { #expect(seg.kind == .added) }
        #expect(segs.map(\.text).joined() == "new content")
    }

    @Test func preservesWhitespaceAsItsOwnSegments() {
        // Whitespace tokens get matched between equal runs so layout is stable
        let segs = PreviewDiff.compute(original: "a b c", refined: "a b c")
        #expect(segs.count == 1)
        #expect(segs.first?.text == "a b c")
    }
}
