import AppKit

final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private var contactField: NSTextField!
    private var intervalControl: NSSegmentedControl!
    var onComplete: (() -> Void)?

    private let intervals = [1, 5, 10, 15, 30, 60]

    func show() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = .windowBackgroundColor

        let contentView = NSView()
        contentView.wantsLayer = true
        window.contentView = contentView

        // Main vertical stack
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 52),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 48),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -48),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -32)
        ])

        // ── Header ──

        let icon = NSTextField(labelWithString: "👁️")
        icon.font = .systemFont(ofSize: 56)
        icon.alignment = .center
        stack.addArrangedSubview(icon)
        stack.setCustomSpacing(12, after: icon)

        let title = NSTextField(labelWithString: "ScreenGuard")
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.alignment = .center
        title.textColor = .labelColor
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(4, after: title)

        let subtitle = NSTextField(labelWithString: "Accountability Screenshot Monitor")
        subtitle.font = .systemFont(ofSize: 14, weight: .medium)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        stack.addArrangedSubview(subtitle)
        stack.setCustomSpacing(16, after: subtitle)

        let desc = NSTextField(wrappingLabelWithString:
            "Random screenshots at the interval you choose. " +
            "Analyzed locally by AI vision. If adult content is " +
            "detected, an iMessage is sent to your accountability contact."
        )
        desc.font = .systemFont(ofSize: 13)
        desc.textColor = .tertiaryLabelColor
        desc.alignment = .center
        stack.addArrangedSubview(desc)
        stack.setCustomSpacing(28, after: desc)

        // ── Separator ──

        let sep = NSBox()
        sep.boxType = .separator
        stack.addArrangedSubview(sep)
        stack.setCustomSpacing(28, after: sep)

        // ── Contact ──

        let contactLabel = NSTextField(labelWithString: "iMessage Contact")
        contactLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        contactLabel.textColor = .labelColor
        stack.addArrangedSubview(contactLabel)
        stack.setCustomSpacing(6, after: contactLabel)

        contactField = NSTextField()
        contactField.placeholderString = "+33 612 345 678 or email@icloud.com"
        contactField.font = .systemFont(ofSize: 14)
        contactField.controlSize = .large
        contactField.wantsLayer = true
        contactField.layer?.cornerRadius = 6
        stack.addArrangedSubview(contactField)
        stack.setCustomSpacing(4, after: contactField)

        let contactHint = NSTextField(labelWithString: "Who gets the alert if content is detected")
        contactHint.font = .systemFont(ofSize: 11)
        contactHint.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(contactHint)
        stack.setCustomSpacing(24, after: contactHint)

        // ── Interval ──

        let intervalLabel = NSTextField(labelWithString: "Check Interval")
        intervalLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        intervalLabel.textColor = .labelColor
        stack.addArrangedSubview(intervalLabel)
        stack.setCustomSpacing(6, after: intervalLabel)

        intervalControl = NSSegmentedControl(
            labels: intervals.map { "\($0)m" },
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        intervalControl.controlSize = .large
        intervalControl.segmentDistribution = .fillEqually
        // Default to 15m (index 3)
        intervalControl.selectedSegment = 3
        stack.addArrangedSubview(intervalControl)
        stack.setCustomSpacing(4, after: intervalControl)

        let intervalHint = NSTextField(labelWithString: "A random screenshot is taken within each window")
        intervalHint.font = .systemFont(ofSize: 11)
        intervalHint.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(intervalHint)
        stack.setCustomSpacing(36, after: intervalHint)

        // ── Button ──

        let startButton = NSButton(title: "  Start Monitoring  ", target: self, action: #selector(startMonitoring))
        startButton.bezelStyle = .rounded
        startButton.controlSize = .large
        startButton.keyEquivalent = "\r"
        startButton.font = .systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(startButton)
        stack.setCustomSpacing(16, after: startButton)

        // ── Footer ──

        let footer = NSTextField(labelWithString: "Requires Screen Recording and Messages permissions")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .quaternaryLabelColor
        footer.alignment = .center
        stack.addArrangedSubview(footer)

        // Show
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(contactField)
    }

    // MARK: - Actions

    @objc private func startMonitoring() {
        let contact = contactField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !contact.isEmpty else {
            shakeField()
            return
        }

        let selectedInterval = intervals[intervalControl.selectedSegment]

        Config.shared.contact = contact
        Config.shared.intervalMinutes = selectedInterval
        Config.shared.onboardingComplete = true

        window.close()
        NSApp.setActivationPolicy(.accessory)

        onComplete?()
    }

    private func shakeField() {
        contactField.wantsLayer = true
        let anim = CAKeyframeAnimation(keyPath: "position.x")
        anim.values = [0, -12, 12, -8, 8, -4, 4, 0]
        anim.duration = 0.5
        anim.isAdditive = true
        contactField.layer?.add(anim, forKey: "shake")
        window.makeFirstResponder(contactField)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // If closed without completing, switch to accessory mode anyway
        if !Config.shared.onboardingComplete {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
