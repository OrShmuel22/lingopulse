import AppKit

@MainActor
enum Alerts {
    private static var lastShown: [String: Date] = [:]
    private static var suppressInterval: TimeInterval {
        let s: Int = AppConfig.shared.value(at: "alerts.suppress_interval_seconds") ?? 300
        return TimeInterval(s)
    }

    static func modal(
        key: String,
        title: String,
        body: String,
        primaryButton: String = "OK",
        secondaryButton: String? = nil,
        onPrimary: (() -> Void)? = nil,
        onSecondary: (() -> Void)? = nil
    ) {
        if let last = lastShown[key], Date().timeIntervalSince(last) < suppressInterval {
            Log.info("Alerts: suppressed '\(key)' (cooldown)")
            return
        }
        lastShown[key] = Date()

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .warning
        alert.addButton(withTitle: primaryButton)
        if let secondaryButton {
            alert.addButton(withTitle: secondaryButton)
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            onPrimary?()
        } else if response == .alertSecondButtonReturn {
            onSecondary?()
        }
    }

    static func toast(_ message: String, duration: TimeInterval = 1.5) {
        ToastWindow.show(message: message, duration: duration)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
private final class ToastWindow {
    private static var current: NSPanel?
    private static var dismissTask: Task<Void, Never>?

    static func show(message: String, duration: TimeInterval) {
        dismissTask?.cancel()
        current?.orderOut(nil)
        current = nil

        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        container.layer?.cornerRadius = 10
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])

        let labelSize = label.intrinsicContentSize
        let width = min(labelSize.width + 32, 480)
        let height = labelSize.height + 20

        let mouse = NSEvent.mouseLocation
        let frame = NSRect(
            x: mouse.x - width / 2,
            y: mouse.y - height - 24,
            width: width,
            height: height
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.contentView = container
        panel.orderFrontRegardless()

        current = panel
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            if Task.isCancelled { return }
            panel.animator().alphaValue = 0
            try? await Task.sleep(for: .milliseconds(250))
            panel.orderOut(nil)
            if current === panel { current = nil }
        }
    }
}
