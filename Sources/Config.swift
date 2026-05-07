import Foundation

/// Persisted configuration via UserDefaults
final class Config {
    static let shared = Config()
    private let d = UserDefaults.standard

    var intervalMinutes: Int {
        get { let v = d.integer(forKey: "sg_interval"); return v > 0 ? v : 15 }
        set { d.set(newValue, forKey: "sg_interval") }
    }

    var contact: String {
        get { d.string(forKey: "sg_contact") ?? "" }
        set { d.set(newValue, forKey: "sg_contact") }
    }

    var model: String {
        get { d.string(forKey: "sg_model") ?? "llava" }
        set { d.set(newValue, forKey: "sg_model") }
    }

    var ollamaPort: Int {
        get { let v = d.integer(forKey: "sg_port"); return v > 0 ? v : 11434 }
        set { d.set(newValue, forKey: "sg_port") }
    }

    var enabled: Bool {
        get {
            if d.object(forKey: "sg_enabled") == nil { return true }
            return d.bool(forKey: "sg_enabled")
        }
        set { d.set(newValue, forKey: "sg_enabled") }
    }

    var detections: Int {
        get { d.integer(forKey: "sg_detections") }
        set { d.set(newValue, forKey: "sg_detections") }
    }

    var lastCheck: Date? {
        get { d.object(forKey: "sg_lastCheck") as? Date }
        set { d.set(newValue, forKey: "sg_lastCheck") }
    }

    var onboardingComplete: Bool {
        get { d.bool(forKey: "sg_onboarded") }
        set { d.set(newValue, forKey: "sg_onboarded") }
    }
}
