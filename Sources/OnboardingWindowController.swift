import AppKit
import CoreGraphics

final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private var stepContent: NSStackView!
    private var dotsLabel: NSTextField!
    private var backButton: NSButton!
    private var nextButton: NSButton!
    private var currentStep = 0
    private let totalSteps = 3

    // Form fields (step 3)
    private var contactField: NSTextField!
    private var intervalControl: NSSegmentedControl!
    private var modelField: NSTextField!

    // Permission indicators (step 2)
    private var screenStatus: NSTextField!
    private var messagesStatus: NSTextField!
    private var screenButton: NSButton!
    private var messagesButton: NSButton!

    var onComplete: (() -> Void)?
    private let intervals = [1, 5, 10, 15, 30, 60]

    // MARK: - Show

    func show() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
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

        let root = NSView()
        root.wantsLayer = true
        window.contentView = root

        // Step content area (fills most of window)
        stepContent = NSStackView()
        stepContent.orientation = .vertical
        stepContent.alignment = .width
        stepContent.spacing = 0
        stepContent.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stepContent)

        // Footer bar
        let footer = buildFooter()
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(footer)

        NSLayoutConstraint.activate([
            stepContent.topAnchor.constraint(equalTo: root.topAnchor, constant: 48),
            stepContent.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 48),
            stepContent.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -48),

            footer.topAnchor.constraint(greaterThanOrEqualTo: stepContent.bottomAnchor, constant: 16),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 48),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -48),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -28),
            footer.heightAnchor.constraint(equalToConstant: 32),
        ])

        showStep(0)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Footer

    private func buildFooter() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.distribution = .fill

        // Dots
        dotsLabel = NSTextField(labelWithString: "")
        dotsLabel.font = .systemFont(ofSize: 18)
        dotsLabel.textColor = .tertiaryLabelColor
        dotsLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        bar.addArrangedSubview(dotsLabel)

        // Spacer
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(spacer)

        // Back button
        backButton = NSButton(title: "Back", target: self, action: #selector(goBack))
        backButton.bezelStyle = .rounded
        backButton.controlSize = .large
        backButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        bar.addArrangedSubview(backButton)

        // Next button
        nextButton = NSButton(title: "Continue", target: self, action: #selector(goNext))
        nextButton.bezelStyle = .rounded
        nextButton.controlSize = .large
        nextButton.keyEquivalent = "\r"
        nextButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        bar.addArrangedSubview(nextButton)

        return bar
    }

    private func updateFooter() {
        // Dots
        let dots = (0..<totalSteps).map { $0 == currentStep ? "●" : "○" }.joined(separator: "  ")
        dotsLabel.stringValue = dots

        // Back visibility
        backButton.isHidden = currentStep == 0

        // Next title
        nextButton.title = currentStep == totalSteps - 1 ? "  Start Monitoring  " : "Continue"
    }

    // MARK: - Navigation

    @objc private func goBack() {
        if currentStep > 0 { showStep(currentStep - 1) }
    }

    @objc private func goNext() {
        switch currentStep {
        case 0, 1:
            showStep(currentStep + 1)
        case 2:
            finishSetup()
        default:
            break
        }
    }

    private func showStep(_ step: Int) {
        currentStep = step

        // Clear content
        stepContent.arrangedSubviews.forEach { $0.removeFromSuperview() }

        switch step {
        case 0: buildWelcomeStep()
        case 1: buildPermissionsStep()
        case 2: buildSetupStep()
        default: break
        }

        updateFooter()
    }

    // MARK: - Step 1: Welcome

    private func buildWelcomeStep() {
        let icon = centeredLabel("👁️", size: 64)
        stepContent.addArrangedSubview(icon)
        stepContent.setCustomSpacing(16, after: icon)

        let title = centeredLabel("ScreenGuard", size: 30, weight: .bold)
        stepContent.addArrangedSubview(title)
        stepContent.setCustomSpacing(4, after: title)

        let subtitle = centeredLabel("Accountability Screenshot Monitor", size: 14, weight: .medium, color: .secondaryLabelColor)
        stepContent.addArrangedSubview(subtitle)
        stepContent.setCustomSpacing(28, after: subtitle)

        let sep = NSBox(); sep.boxType = .separator
        stepContent.addArrangedSubview(sep)
        stepContent.setCustomSpacing(28, after: sep)

        let bullets: [(String, String)] = [
            ("🎲", "Takes a screenshot at a random second within each interval"),
            ("🧠", "Analyzes the image locally with an AI vision model"),
            ("📱", "Sends an iMessage alert if adult content is detected"),
        ]

        for (i, (emoji, text)) in bullets.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 12

            let emojiLabel = NSTextField(labelWithString: emoji)
            emojiLabel.font = .systemFont(ofSize: 22)
            emojiLabel.setContentHuggingPriority(.required, for: .horizontal)
            emojiLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            row.addArrangedSubview(emojiLabel)

            let desc = NSTextField(wrappingLabelWithString: text)
            desc.font = .systemFont(ofSize: 14)
            desc.textColor = .secondaryLabelColor
            row.addArrangedSubview(desc)

            stepContent.addArrangedSubview(row)
            stepContent.setCustomSpacing(i < bullets.count - 1 ? 16 : 28, after: row)
        }

        let sep2 = NSBox(); sep2.boxType = .separator
        stepContent.addArrangedSubview(sep2)
        stepContent.setCustomSpacing(20, after: sep2)

        let privacy = centeredLabel("🔒  Everything stays on your Mac. No cloud. No tracking.", size: 12, weight: .medium, color: .tertiaryLabelColor)
        stepContent.addArrangedSubview(privacy)
    }

    // MARK: - Step 2: Permissions

    private func buildPermissionsStep() {
        let icon = centeredLabel("🔐", size: 56)
        stepContent.addArrangedSubview(icon)
        stepContent.setCustomSpacing(12, after: icon)

        let title = centeredLabel("Permissions", size: 28, weight: .bold)
        stepContent.addArrangedSubview(title)
        stepContent.setCustomSpacing(4, after: title)

        let subtitle = centeredLabel("ScreenGuard needs two macOS permissions", size: 14, weight: .medium, color: .secondaryLabelColor)
        stepContent.addArrangedSubview(subtitle)
        stepContent.setCustomSpacing(32, after: subtitle)

        // ── Screen Recording ──
        let screenCard = buildPermissionCard(
            icon: "🖥",
            title: "Screen Recording",
            description: "Captures screenshots of your display for analysis",
            granted: CGPreflightScreenCaptureAccess(),
            action: #selector(grantScreenRecording),
            statusField: &screenStatus,
            actionButton: &screenButton
        )
        stepContent.addArrangedSubview(screenCard)
        stepContent.setCustomSpacing(16, after: screenCard)

        // ── Messages ──
        let msgGranted = checkMessagesAccess()
        let msgCard = buildPermissionCard(
            icon: "💬",
            title: "Messages Automation",
            description: "Sends iMessage alerts to your accountability contact",
            granted: msgGranted,
            action: #selector(grantMessages),
            statusField: &messagesStatus,
            actionButton: &messagesButton
        )
        stepContent.addArrangedSubview(msgCard)
        stepContent.setCustomSpacing(24, after: msgCard)

        // Refresh button
        let refreshRow = NSStackView()
        refreshRow.orientation = .horizontal
        refreshRow.alignment = .centerY

        let refreshButton = NSButton(title: "↻  Check Again", target: self, action: #selector(refreshPermissions))
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .regular
        refreshRow.addArrangedSubview(refreshButton)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        refreshRow.addArrangedSubview(spacer)

        stepContent.addArrangedSubview(refreshRow)
        stepContent.setCustomSpacing(16, after: refreshRow)

        let hint = centeredLabel("You can always grant these later in\nSystem Settings → Privacy & Security", size: 11, color: .tertiaryLabelColor)
        stepContent.addArrangedSubview(hint)
    }

    private func buildPermissionCard(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
        action: Selector,
        statusField: inout NSTextField!,
        actionButton: inout NSButton!
    ) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])

        // Title row
        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY

        let iconLabel = NSTextField(labelWithString: icon)
        iconLabel.font = .systemFont(ofSize: 24)
        iconLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleRow.addArrangedSubview(iconLabel)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleRow.addArrangedSubview(titleLabel)

        let titleSpacer = NSView()
        titleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleRow.addArrangedSubview(titleSpacer)

        let status = NSTextField(labelWithString: granted ? "✅ Granted" : "⚠️ Required")
        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.textColor = granted ? .systemGreen : .systemOrange
        status.setContentHuggingPriority(.required, for: .horizontal)
        titleRow.addArrangedSubview(status)
        statusField = status

        stack.addArrangedSubview(titleRow)
        stack.setCustomSpacing(6, after: titleRow)

        // Description
        let desc = NSTextField(labelWithString: description)
        desc.font = .systemFont(ofSize: 12)
        desc.textColor = .secondaryLabelColor
        stack.addArrangedSubview(desc)

        // Grant button (only if not granted)
        let btn = NSButton(title: "Open Settings", target: self, action: action)
        btn.bezelStyle = .rounded
        btn.controlSize = .regular
        btn.isHidden = granted
        actionButton = btn

        stack.setCustomSpacing(10, after: desc)
        stack.addArrangedSubview(btn)

        return card
    }

    @objc private func grantScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    @objc private func grantMessages() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func refreshPermissions() {
        let screenOK = CGPreflightScreenCaptureAccess()
        screenStatus.stringValue = screenOK ? "✅ Granted" : "⚠️ Required"
        screenStatus.textColor = screenOK ? .systemGreen : .systemOrange
        screenButton.isHidden = screenOK

        let msgOK = checkMessagesAccess()
        messagesStatus.stringValue = msgOK ? "✅ Granted" : "⚠️ Required"
        messagesStatus.textColor = msgOK ? .systemGreen : .systemOrange
        messagesButton.isHidden = msgOK
    }

    private func checkMessagesAccess() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Messages\" to get name"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Step 3: Setup

    private func buildSetupStep() {
        let icon = centeredLabel("⚙️", size: 56)
        stepContent.addArrangedSubview(icon)
        stepContent.setCustomSpacing(12, after: icon)

        let title = centeredLabel("Configuration", size: 28, weight: .bold)
        stepContent.addArrangedSubview(title)
        stepContent.setCustomSpacing(4, after: title)

        let subtitle = centeredLabel("Set your accountability contact and preferences", size: 14, weight: .medium, color: .secondaryLabelColor)
        stepContent.addArrangedSubview(subtitle)
        stepContent.setCustomSpacing(28, after: subtitle)

        let sep = NSBox(); sep.boxType = .separator
        stepContent.addArrangedSubview(sep)
        stepContent.setCustomSpacing(28, after: sep)

        // ── Contact ──
        let contactLabel = NSTextField(labelWithString: "iMessage Contact")
        contactLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        stepContent.addArrangedSubview(contactLabel)
        stepContent.setCustomSpacing(6, after: contactLabel)

        contactField = NSTextField()
        contactField.placeholderString = "+33 612 345 678 or email@icloud.com"
        contactField.font = .systemFont(ofSize: 14)
        contactField.controlSize = .large
        contactField.wantsLayer = true
        if !Config.shared.contact.isEmpty {
            contactField.stringValue = Config.shared.contact
        }
        stepContent.addArrangedSubview(contactField)
        stepContent.setCustomSpacing(4, after: contactField)

        let contactHint = NSTextField(labelWithString: "Who receives the alert if content is detected")
        contactHint.font = .systemFont(ofSize: 11)
        contactHint.textColor = .tertiaryLabelColor
        stepContent.addArrangedSubview(contactHint)
        stepContent.setCustomSpacing(24, after: contactHint)

        // ── Interval ──
        let intervalLabel = NSTextField(labelWithString: "Check Interval")
        intervalLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        stepContent.addArrangedSubview(intervalLabel)
        stepContent.setCustomSpacing(6, after: intervalLabel)

        intervalControl = NSSegmentedControl(
            labels: intervals.map { "\($0)m" },
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        intervalControl.controlSize = .large
        intervalControl.segmentDistribution = .fillEqually
        let savedInterval = Config.shared.intervalMinutes
        intervalControl.selectedSegment = intervals.firstIndex(of: savedInterval) ?? 3
        stepContent.addArrangedSubview(intervalControl)
        stepContent.setCustomSpacing(4, after: intervalControl)

        let intervalHint = NSTextField(labelWithString: "A random screenshot is taken within each window")
        intervalHint.font = .systemFont(ofSize: 11)
        intervalHint.textColor = .tertiaryLabelColor
        stepContent.addArrangedSubview(intervalHint)
        stepContent.setCustomSpacing(24, after: intervalHint)

        // ── Vision Model ──
        let modelLabel = NSTextField(labelWithString: "Vision Model")
        modelLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        stepContent.addArrangedSubview(modelLabel)
        stepContent.setCustomSpacing(6, after: modelLabel)

        modelField = NSTextField()
        modelField.stringValue = Config.shared.model
        modelField.placeholderString = "llava"
        modelField.font = .systemFont(ofSize: 14)
        modelField.controlSize = .large
        modelField.wantsLayer = true
        stepContent.addArrangedSubview(modelField)
        stepContent.setCustomSpacing(4, after: modelField)

        let modelHint = NSTextField(labelWithString: "Ollama model with vision support (e.g. llava, minicpm-v)")
        modelHint.font = .systemFont(ofSize: 11)
        modelHint.textColor = .tertiaryLabelColor
        stepContent.addArrangedSubview(modelHint)

        // Focus contact field
        window.makeFirstResponder(contactField)
    }

    // MARK: - Finish

    private func finishSetup() {
        let contact = contactField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !contact.isEmpty else {
            shakeField(contactField)
            return
        }

        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        Config.shared.contact = contact
        Config.shared.intervalMinutes = intervals[intervalControl.selectedSegment]
        Config.shared.model = model.isEmpty ? "llava" : model
        Config.shared.onboardingComplete = true

        window.close()
        NSApp.setActivationPolicy(.accessory)
        onComplete?()
    }

    private func shakeField(_ field: NSTextField) {
        field.wantsLayer = true
        let anim = CAKeyframeAnimation(keyPath: "position.x")
        anim.values = [0, -12, 12, -8, 8, -4, 4, 0]
        anim.duration = 0.5
        anim.isAdditive = true
        field.layer?.add(anim, forKey: "shake")
        window.makeFirstResponder(field)
    }

    // MARK: - Helpers

    private func centeredLabel(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = .center
        return label
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if !Config.shared.onboardingComplete {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
