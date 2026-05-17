import AppKit
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var onboarding: OnboardingWindowController?
    private var testModeActive = false
    private var testTimer: Timer?
    private let screenshotDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenGuard_Screenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()

        if Config.shared.onboardingComplete {
            startMonitoring()
        } else {
            showOnboarding()
        }
    }

    private func showOnboarding() {
        onboarding = OnboardingWindowController()
        onboarding?.onComplete = { [weak self] in
            self?.onboarding = nil
            self?.rebuildMenu()
            self?.startMonitoring()
        }
        onboarding?.show()
    }

    private func startMonitoring() {
        if Config.shared.enabled {
            scheduleNext()
        }
        sgLog.info("Active — interval: \(Config.shared.intervalMinutes)m, contact: \(Config.shared.contact), model: \(Config.shared.model)")
    }

    // MARK: - Status Bar

    private var menu: NSMenu?

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "eye",
                accessibilityDescription: "ScreenGuard"
            )
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp])
        }

        rebuildMenu()
    }

    @objc private func statusItemClicked() {
        if testModeActive {
            deactivateTestMode()
            return
        }
        // Show the menu programmatically
        guard let button = statusItem.button, let menu = self.menu else { return }
        statusItem.menu = menu
        button.performClick(nil)
        // Remove after showing so future clicks go through our action
        statusItem.menu = nil
    }

    private func rebuildMenu() {
        let newMenu = NSMenu()
        let config = Config.shared

        if !config.onboardingComplete {
            let setupItem = NSMenuItem(title: "⚠️ Complete Setup...", action: #selector(openSetup), keyEquivalent: "")
            setupItem.target = self
            newMenu.addItem(setupItem)
            newMenu.addItem(.separator())
        }

        let toggleTitle = config.enabled ? "✅ Monitoring Active" : "⏸ Monitoring Paused"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleMonitoring), keyEquivalent: "")
        toggle.target = self
        newMenu.addItem(toggle)

        newMenu.addItem(.separator())

        let intervalItem = NSMenuItem(title: "Interval: \(config.intervalMinutes) min", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        for mins in [1, 5, 10, 15, 30, 60] {
            let item = NSMenuItem(title: "\(mins) min", action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mins
            if mins == config.intervalMinutes { item.state = .on }
            intervalMenu.addItem(item)
        }
        intervalItem.submenu = intervalMenu
        newMenu.addItem(intervalItem)

        let contactDisplay = config.contact.isEmpty ? "Not set ⚠️" : config.contact
        let contactItem = NSMenuItem(title: "Contact: \(contactDisplay)", action: #selector(promptSetContact), keyEquivalent: "")
        contactItem.target = self
        newMenu.addItem(contactItem)

        newMenu.addItem(.separator())

        // Test Mode
        let testItem = NSMenuItem(title: "🔍 Test Mode", action: #selector(activateTestMode), keyEquivalent: "t")
        testItem.target = self
        newMenu.addItem(testItem)

        // Review Screenshots
        let reviewItem = NSMenuItem(title: "📂 Review Screenshots in Finder", action: #selector(openScreenshots), keyEquivalent: "")
        reviewItem.target = self
        newMenu.addItem(reviewItem)

        if config.detections > 0 {
            newMenu.addItem(.separator())
            let detItem = NSMenuItem(title: "⚠️ Detections: \(config.detections)", action: nil, keyEquivalent: "")
            detItem.isEnabled = false
            newMenu.addItem(detItem)
        }

        newMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit ScreenGuard", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        newMenu.addItem(quitItem)

        self.menu = newMenu
    }

    // MARK: - Menu Actions

    @objc private func openSetup() {
        NSApp.setActivationPolicy(.regular)
        showOnboarding()
    }

    @objc private func toggleMonitoring() {
        Config.shared.enabled.toggle()
        if Config.shared.enabled {
            scheduleNext()
            sgLog.info("Monitoring resumed")
        } else {
            timer?.invalidate()
            timer = nil
            sgLog.info("Monitoring paused")
            MessageService.shared.sendTamperAlert(to: Config.shared.contact, action: "MONITORING PAUSED")
        }
        rebuildMenu()
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        let old = Config.shared.intervalMinutes
        Config.shared.intervalMinutes = sender.tag
        timer?.invalidate()
        timer = nil
        if Config.shared.enabled { scheduleNext() }
        rebuildMenu()
        if sender.tag != old {
            MessageService.shared.sendTamperAlert(to: Config.shared.contact, action: "INTERVAL CHANGED: \(old)m → \(sender.tag)m")
        }
    }

    @objc private func promptSetContact() {
        if let value = showInputDialog(
            title: "Set Contact",
            message: "Phone number or Apple ID for iMessage alerts:",
            defaultValue: Config.shared.contact
        ) {
            Config.shared.contact = value
            rebuildMenu()
        }
    }

    @objc private func activateTestMode() {
        testModeActive = true
        // Show initial "..." while first capture runs
        if let button = statusItem.button {
            button.image = nil
            button.title = "..."
        }
        // Run a capture immediately, then every second
        runTestCapture()
        testTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.runTestCapture()
        }
        sgLog.info("Test mode activated")
    }

    private func deactivateTestMode() {
        testModeActive = false
        testTimer?.invalidate()
        testTimer = nil
        // Restore normal icon
        if let button = statusItem.button {
            button.title = ""
            button.image = NSImage(
                systemSymbolName: "eye",
                accessibilityDescription: "ScreenGuard"
            )
        }
        sgLog.info("Test mode deactivated")
    }

    private func runTestCapture() {
        Task { @MainActor in
            let score: Float = await Task.detached {
                guard let cgImage = CGDisplayCreateImage(CGMainDisplayID()) else { return Float(0) }
                guard ContentAnalyzer.shared.isModelLoaded else { return Float(0) }
                _ = ContentAnalyzer.shared.analyze(cgImage: cgImage)
                return ContentAnalyzer.shared.lastNSFWScore
            }.value

            guard testModeActive else { return }
            if let button = statusItem.button {
                button.title = String(format: "%.0f%%", score * 100)
            }
        }
    }

    @objc private func openScreenshots() {
        NSWorkspace.shared.open(screenshotDir)
    }

    @objc private func quit() {
        MessageService.shared.sendTamperAlert(to: Config.shared.contact, action: "APP CLOSED")
        // Give iMessage time to send
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Scheduling

    private func scheduleNext() {
        timer?.invalidate()
        let intervalSec = Double(Config.shared.intervalMinutes * 60)
        let delay = Double.random(in: 10...max(11, intervalSec))

        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.captureAndAnalyze()
                if Config.shared.enabled {
                    self?.scheduleNext()
                }
            }
        }
    }

    // MARK: - Capture & Analyze

    private enum CaptureResult {
        case analyzed(Bool)
        case captureFailed
        case modelMissing
    }

    private func captureAndAnalyze() async {
        // Use CGDisplayCreateImage — unlike ScreenCaptureKit it reads the
        // framebuffer directly without window-server IPC, so it never
        // steals focus from the foreground app.
        let screenshotDir = self.screenshotDir
        let result: CaptureResult = await Task.detached { () -> CaptureResult in
            guard let cgImage = CGDisplayCreateImage(CGMainDisplayID()) else {
                sgLog.error("Screen capture failed: CGDisplayCreateImage returned nil")
                return .captureFailed
            }

            // Save screenshot for review (keep last 5 minutes)
            Self.saveScreenshot(cgImage, to: screenshotDir)
            Self.pruneScreenshots(in: screenshotDir, olderThan: 300)

            // CoreML NSFW detection
            guard ContentAnalyzer.shared.isModelLoaded else {
                sgLog.error("NSFW model not available")
                return .modelMissing
            }

            return .analyzed(ContentAnalyzer.shared.analyze(cgImage: cgImage))
        }.value

        switch result {
        case .captureFailed:
            if !Config.shared.didAlertRecordingRevoked {
                Config.shared.didAlertRecordingRevoked = true
                MessageService.shared.sendTamperAlert(
                    to: Config.shared.contact,
                    action: "SCREEN RECORDING REVOKED — cannot capture screenshots")
            }
            return
        case .modelMissing:
            if !Config.shared.didAlertModelMissing {
                Config.shared.didAlertModelMissing = true
                MessageService.shared.sendTamperAlert(
                    to: Config.shared.contact,
                    action: "NSFW MODEL MISSING — detection disabled")
            }
            return
        case .analyzed(let isNSFW):
            Config.shared.lastCheck = Date()
            // Permission restored — re-arm alerts for future revocations
            Config.shared.didAlertRecordingRevoked = false
            Config.shared.didAlertModelMissing = false
            guard isNSFW else {
                sgLog.info("Clean")
                return
            }
        }

        // NSFW detected
        Config.shared.detections += 1
        sgLog.error("NSFW CONTENT DETECTED!")
        let contact = Config.shared.contact
        Task.detached {
            MessageService.shared.sendAlert(to: contact)
        }
        flashIcon()
        rebuildMenu()
    }

    // MARK: - Helpers

    private func flashIcon() {
        guard let button = statusItem.button else { return }
        let original = button.image
        button.image = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: "Detection!"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            button.image = original
        }
    }

    private static func saveScreenshot(_ image: CGImage, to dir: URL) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH-mm-ss"
        let name = formatter.string(from: Date()) + ".jpg"
        let url = dir.appendingPathComponent(name)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.5] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    private static func pruneScreenshots(in dir: URL, olderThan seconds: TimeInterval) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-seconds)
        for file in files {
            guard let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
                  let created = attrs.creationDate,
                  created < cutoff else { continue }
            try? fm.removeItem(at: file)
        }
    }

    private func showInputDialog(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = defaultValue
        field.placeholderString = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
