import AppKit
import CoreGraphics
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var onboarding: OnboardingWindowController?

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

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "eye",
                accessibilityDescription: "ScreenGuard"
            )
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let config = Config.shared

        if !config.onboardingComplete {
            let setupItem = NSMenuItem(title: "⚠️ Complete Setup...", action: #selector(openSetup), keyEquivalent: "")
            setupItem.target = self
            menu.addItem(setupItem)
            menu.addItem(.separator())
        }

        let toggleTitle = config.enabled ? "✅ Monitoring Active" : "⏸ Monitoring Paused"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleMonitoring), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

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

        let contactDisplay = config.contact.isEmpty ? "Not set ⚠️" : config.contact
        let contactItem = NSMenuItem(title: "Contact: \(contactDisplay)", action: #selector(promptSetContact), keyEquivalent: "")
        contactItem.target = self
        menu.addItem(contactItem)

        if config.detections > 0 {
            menu.addItem(.separator())
            let detItem = NSMenuItem(title: "⚠️ Detections: \(config.detections)", action: nil, keyEquivalent: "")
            detItem.isEnabled = false
            menu.addItem(detItem)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit ScreenGuard", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
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

    private func captureAndAnalyze() async {
        let cgImage: CGImage
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                sgLog.error("No display found")
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height

            cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            sgLog.error("Screen capture failed: \(error.localizedDescription, privacy: .public)")
            // Alert contact that screen recording was revoked
            MessageService.shared.sendTamperAlert(to: Config.shared.contact, action: "SCREEN RECORDING REVOKED — cannot capture screenshots")
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
            return
        }

        Config.shared.lastCheck = Date()

        // CoreML NSFW detection — runs in milliseconds
        guard ContentAnalyzer.shared.isModelLoaded else {
            sgLog.error("NSFW model not available")
            MessageService.shared.sendTamperAlert(to: Config.shared.contact, action: "NSFW MODEL MISSING — detection disabled")
            return
        }
        let isNSFW = ContentAnalyzer.shared.analyze(cgImage: cgImage)

        if isNSFW {
            Config.shared.detections += 1
            sgLog.error("NSFW CONTENT DETECTED!")
            MessageService.shared.sendAlert(to: Config.shared.contact)
            flashIcon()
        } else {
            sgLog.info("Clean")
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
