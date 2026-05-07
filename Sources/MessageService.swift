import Foundation

/// Sends iMessage alerts via AppleScript
final class MessageService {
    static let shared = MessageService()

    func sendAlert(to contact: String) {
        guard !contact.isEmpty else {
            sgLog.warning("No contact configured — skipping alert")
            return
        }

        let escaped = contact.replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
            tell application "Messages"
                send "🚨 PORN DETECTED" to buddy "\(escaped)" of (service 1 whose service type is iMessage)
            end tell
            """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                sgLog.info("Alert sent to \(contact)")
            } else {
                sgLog.error("osascript exited with status \(process.terminationStatus)")
            }
        } catch {
            sgLog.error("Failed to send iMessage: \(error.localizedDescription)")
        }
    }
}
