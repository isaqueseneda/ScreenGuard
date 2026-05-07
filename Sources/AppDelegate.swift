import AppKit
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var nextCheckDate: Date?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()

        // Prompt for contact on first launch
        if Config.shared.contact.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.promptSetContact()
            }
        }

        if Config.shared.enabled {
            scheduleNext()
        }

        print("[ScreenGuard] Started — interval: \(Config.shared.intervalMinutes)m, model: \(Config.shared.model)")
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "eye.trianglebadge.exclamationmark",
                accessibilityDescription: "ScreenGuard"
            )
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let config = Config.shared

        // Toggle
        let toggleTitle = config.enabled ? "✅ Monitoring Active" : "⏸ Monitoring Paused"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleMonitoring), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        // Interval submenu
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
        menu.addItem(intervalItem)

        // Contact
        let contactDisplay = config.contact.isEmpty ? "Not set ⚠️" : config.contact
        let contactItem = NSMenuItem(title: "Contact: \(contactDisplay)", action: #selector(promptSetContact), keyEquivalent: "")
        contactItem.target = self
        menu.addItem(contactItem)

        // Model
        let modelItem = NSMenuItem(title: "Model: \(config.model)", action: #selector(promptSetModel), keyEquivalent: "")
        modelItem.target = self
        menu.addItem(modelItem)

        menu.addItem(.separator())

        // Status info
        let lastText = formatLastCheck()
        let lastItem = NSMenuItem(title: lastText, action: nil, keyEquivalent: "")
        lastItem.isEnabled = false
        menu.addItem(lastItem)

        let detItem = NSMenuItem(title: "Detections: \(config.detections)", action: nil, keyEquivalent: "")
        detItem.isEnabled = false
        menu.addItem(detItem)

        let nextText = formatNextCheck()
        let nextItem = NSMenuItem(title: nextText, action: nil, keyEquivalent: "")
        nextItem.isEnabled = false
        menu.addItem(nextItem)

        menu.addItem(.separator())

        // Manual trigger
        let captureItem = NSMenuItem(title: "📸 Capture Now", action: #selector(captureNow), keyEquivalent: "t")
        captureItem.target = self
        menu.addItem(captureItem)

        // Reset detections
        if config.detections > 0 {
            let resetItem = NSMenuItem(title: "Reset Detection Count", action: #selector(resetDetections), keyEquivalent: "")
            resetItem.target = self
            menu.addItem(resetItem)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit ScreenGuard", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Menu Actions

    @objc private func toggleMonitoring() {
        Config.shared.enabled.toggle()
        if Config.shared.enabled {
            scheduleNext()
            print("[ScreenGuard] Monitoring resumed")
        } else {
            timer?.invalidate()
            timer = nil
            nextCheckDate = nil
            print("[ScreenGuard] Monitoring paused")
        }
        rebuildMenu()
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        Config.shared.intervalMinutes = sender.tag
        timer?.invalidate()
        timer = nil
        if Config.shared.enabled { scheduleNext() }
        rebuildMenu()
        print("[ScreenGuard] Interval → \(sender.tag)m")
    }

    @objc private func promptSetContact() {
        if let value = showInputDialog(
            title: "Set Contact",
            message: "Phone number or Apple ID for iMessage alerts:",
            defaultValue: Config.shared.contact
        ) {
            Config.shared.contact = value
            rebuildMenu()
            print("[ScreenGuard] Contact → \(value)")
        }
    }

    @objc private func promptSetModel() {
        if let value = showInputDialog(
            title: "Set Vision Model",
            message: "Ollama vision model name (e.g. llava, minicpm-v, gemma3):",
            defaultValue: Config.shared.model
        ) {
            Config.shared.model = value
            rebuildMenu()
            print("[ScreenGuard] Model → \(value)")
        }
    }

    @objc private func captureNow() {
        Task { await captureAndAnalyze() }
    }

    @objc private func resetDetections() {
        Config.shared.detections = 0
        rebuildMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Scheduling

    private func scheduleNext() {
        timer?.invalidate()
        let intervalSec = Double(Config.shared.intervalMinutes * 60)
        let delay = Double.random(in: 10...max(11, intervalSec))
        nextCheckDate = Date().addingTimeInterval(delay)

        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.captureAndAnalyze()
                if Config.shared.enabled {
                    self?.scheduleNext()
                }
            }
        }

        print("[ScreenGuard] Next capture in \(Int(delay))s")
    }

    // MARK: - Capture & Analyze

    private func captureAndAnalyze() async {
        // Check screen capture permission
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            print("[ScreenGuard] ⚠️ Screen Recording permission required — check System Settings > Privacy")
            return
        }

        // Take screenshot
        guard let cgImage = CGWindowListCreateImage(
            .infinite, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]
        ) else {
            print("[ScreenGuard] Failed to capture screenshot")
            return
        }

        // Convert to JPEG
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.5]) else {
            print("[ScreenGuard] Failed to encode JPEG")
            return
        }

        Config.shared.lastCheck = Date()
        print("[ScreenGuard] 📸 Captured (\(jpeg.count / 1024) KB) — analyzing...")
        rebuildMenu()

        // Send to Ollama
        let isNSFW = await ContentAnalyzer.shared.analyze(imageData: jpeg)

        if isNSFW {
            Config.shared.detections += 1
            print("[ScreenGuard] 🚨 NSFW CONTENT DETECTED!")
            MessageService.shared.sendAlert(to: Config.shared.contact)
            flashIcon()
        } else {
            print("[ScreenGuard] ✓ Clean")
        }

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

    private func formatLastCheck() -> String {
        guard let last = Config.shared.lastCheck else { return "Last check: never" }
        let ago = Int(Date().timeIntervalSince(last))
        if ago < 60 { return "Last check: \(ago)s ago" }
        return "Last check: \(ago / 60)m ago"
    }

    private func formatNextCheck() -> String {
        guard let next = nextCheckDate, Config.shared.enabled else { return "Next check: —" }
        let secs = Int(next.timeIntervalSinceNow)
        guard secs > 0 else { return "Next check: imminent" }
        return "Next check: ~\(secs / 60)m \(secs % 60)s"
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
