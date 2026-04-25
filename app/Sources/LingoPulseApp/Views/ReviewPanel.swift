import AppKit
import SwiftUI
import ApplicationServices

// MARK: - ReviewPanel (window management)

@MainActor
final class ReviewPanel {
    private var window: NSPanel?
    private var hostingController: NSHostingController<ReviewPanelView>?
    private var stateModel: ReviewPanelState?

    func show(state: ReviewPanelState) {
        hide()
        self.stateModel = state

        let panel = NSPanel(
            contentRect: NSRect(
                x: 0, y: 0,
                width: Constants.Layout.reviewPanelWidth,
                height: Constants.Layout.reviewPanelHeight
            ),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "LingoPulse — \(state.result.edits.count) Suggestions"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.hasShadow = true

        let view = ReviewPanelView(state: state)
        let hc = NSHostingController(rootView: view)
        hc.view.frame = panel.contentView?.bounds ?? .zero
        hc.view.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hc.view)

        if let screen = NSScreen.main {
            let origin = CGPoint(
                x: screen.frame.midX - Constants.Layout.reviewPanelWidth / 2,
                y: screen.frame.midY - Constants.Layout.reviewPanelHeight / 2
            )
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()

        self.window = panel
        self.hostingController = hc
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        hostingController = nil
        stateModel = nil
    }
}

// MARK: - ReviewPanelState (ObservableObject)

@MainActor
final class ReviewPanelState: ObservableObject {
    let result: RefineResult
    @Published var perEditAccepted: [Bool]
    @Published var currentRowIndex: Int = 0

    var onAcceptAll: (() -> Void)?
    var onAcceptSafe: (() -> Void)?
    var onDismissAll: (() -> Void)?

    init(result: RefineResult) {
        self.result = result
        self.perEditAccepted = Array(repeating: false, count: result.edits.count)
    }

    var acceptedIndices: [Int] {
        perEditAccepted.enumerated().compactMap { $0.element ? $0.offset : nil }
    }

    var safeIndices: [Int] {
        result.edits.enumerated()
            .filter { $0.element.riskEnum == .safe }
            .map { $0.offset }
    }

    func cursorNext() {
        guard !result.edits.isEmpty else { return }
        currentRowIndex = (currentRowIndex + 1) % result.edits.count
    }

    func cursorPrev() {
        guard !result.edits.isEmpty else { return }
        currentRowIndex = (currentRowIndex - 1 + result.edits.count) % result.edits.count
    }

    func toggleCurrent() {
        guard currentRowIndex < perEditAccepted.count else { return }
        perEditAccepted[currentRowIndex] = !perEditAccepted[currentRowIndex]
    }
}

// MARK: - ReviewPanelView (SwiftUI)

struct ReviewPanelView: View {
    @ObservedObject var state: ReviewPanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    contextDiff
                    Divider()
                    editList
                }
                .padding(16)
            }
        }
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            Text("\(state.result.edits.count) suggestions")
                .font(.headline)
            Spacer()
            Button("Accept Safe (\(state.safeIndices.count))") {
                for idx in state.safeIndices { state.perEditAccepted[idx] = true }
                state.onAcceptSafe?()
            }
            Button("Accept All") {
                for i in 0..<state.perEditAccepted.count { state.perEditAccepted[i] = true }
                state.onAcceptAll?()
            }
            Button("Dismiss") {
                state.onDismissAll?()
            }
        }
        .padding(12)
    }

    // MARK: Context diff

    private var contextDiff: some View {
        Text(buildAttributedDiff())
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func buildAttributedDiff() -> AttributedString {
        let originalWords = state.result.original
            .split(separator: " ", omittingEmptySubsequences: false)
            .map(String.init)
        var attributed = AttributedString()

        for (wordIdx, word) in originalWords.enumerated() {
            // Find the first edit whose from_span covers this word index
            let matchingEdit = state.result.edits.enumerated().first { (editIdx, edit) in
                guard edit.from_span.count >= 2 else { return false }
                return wordIdx >= edit.from_span[0] && wordIdx < edit.from_span[1]
            }

            var part = AttributedString(word)
            if let (editIdx, edit) = matchingEdit {
                if state.perEditAccepted[editIdx] {
                    part.foregroundColor = .systemGreen
                } else if edit.riskEnum == .risky {
                    part.foregroundColor = .systemRed
                    part.backgroundColor = Color.red.opacity(0.1)
                } else {
                    part.strikethroughStyle = .single
                    part.foregroundColor = .secondaryLabelColor
                }
            }
            attributed.append(part)
            if wordIdx < originalWords.count - 1 {
                attributed.append(AttributedString(" "))
            }
        }
        return attributed
    }

    // MARK: Edit list

    private var editList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(state.result.edits.enumerated()), id: \.offset) { idx, edit in
                editRow(idx: idx, edit: edit)
            }
        }
    }

    private func editRow(idx: Int, edit: Edit) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { state.perEditAccepted[idx] },
                set: { newVal in
                    state.perEditAccepted[idx] = newVal
                }
            ))
            .labelsHidden()

            Text(edit.from_text)
                .strikethrough()
                .foregroundStyle(.secondary)
            Text("→")
                .foregroundStyle(.secondary)
            Text(edit.to_text)
                .fontWeight(.semibold)

            Spacer()

            confidenceBadge(edit.confidenceEnum)
            categoryPill(edit.categoryEnum)

            if edit.riskEnum == .risky {
                Text("REVIEW")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.red))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(strokeColor(for: idx, edit: edit), lineWidth: idx == state.currentRowIndex ? 2.5 : 1.5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))
        )
    }

    private func strokeColor(for idx: Int, edit: Edit) -> Color {
        if idx == state.currentRowIndex { return Color.accentColor }
        if edit.riskEnum == .risky { return Color.red }
        return Color.clear
    }

    // MARK: Badges

    private func confidenceBadge(_ confidence: Confidence) -> some View {
        Group {
            switch confidence {
            case .high:
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            case .medium:
                Image(systemName: "questionmark.circle").foregroundStyle(.orange)
            case .low:
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
            }
        }
        .font(.system(size: 14))
    }

    private func categoryPill(_ category: EditCategory) -> some View {
        Text(category.rawValue.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(categoryColor(category)))
    }

    private func categoryColor(_ category: EditCategory) -> Color {
        switch category {
        case .preposition, .comparative: return Color.blue.opacity(0.85)
        case .plural:                    return Color.green.opacity(0.85)
        case .calque:                    return Color.orange.opacity(0.85)
        case .structure:                 return Color.purple.opacity(0.85)
        case .typo:                      return Color.red.opacity(0.85)
        case .apostrophe:                return Color(.darkGray)
        case .capitalization:            return Color.teal.opacity(0.85)
        case .grammar, .other:           return Color.gray
        }
    }
}
