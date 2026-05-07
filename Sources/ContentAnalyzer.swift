import Foundation

/// Sends screenshot to Ollama vision model for NSFW analysis
final class ContentAnalyzer {
    static let shared = ContentAnalyzer()

    func analyze(imageData: Data) async -> Bool {
        let config = Config.shared
        let base64 = imageData.base64EncodedString()

        guard let url = URL(string: "http://localhost:\(config.ollamaPort)/api/generate") else {
            print("[ScreenGuard] Invalid Ollama URL")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": config.model,
            "prompt": """
                Analyze this screenshot. Does it contain pornographic content, nudity, \
                or sexually explicit material (naked bodies, sex acts, genitalia, erotic content)? \
                Answer with ONLY the word YES or NO. Nothing else.
                """,
            "images": [base64],
            "stream": false
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let response = json["response"] as? String {
                let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                print("[ScreenGuard] Ollama response: \(trimmed)")
                return trimmed.hasPrefix("YES")
            }
        } catch {
            print("[ScreenGuard] Ollama error: \(error.localizedDescription)")
        }

        return false
    }
}
