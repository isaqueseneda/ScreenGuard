import AppKit

let app = NSApplication.shared

// Regular mode for onboarding window, accessory (menu bar only) after
if Config.shared.onboardingComplete {
    app.setActivationPolicy(.accessory)
} else {
    app.setActivationPolicy(.regular)
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
