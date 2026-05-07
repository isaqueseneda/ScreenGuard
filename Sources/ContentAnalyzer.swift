import CoreML
import Vision
import AppKit

/// Uses Yahoo's Open NSFW CoreML model for instant NSFW detection
final class ContentAnalyzer {
    static let shared = ContentAnalyzer()

    private var visionModel: VNCoreMLModel?
    private let threshold: Float = 0.25

    init() {
        loadModel()
    }

    private func loadModel() {
        guard let url = findModelURL() else {
            sgLog.error("OpenNSFW.mlmodelc not found in any search path")
            return
        }

        do {
            let mlModel = try MLModel(contentsOf: url)
            visionModel = try VNCoreMLModel(for: mlModel)
            sgLog.info("NSFW model loaded from \(url.path, privacy: .public)")
        } catch {
            sgLog.error("Failed to load NSFW model: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func findModelURL() -> URL? {
        // 1. App bundle Contents/Resources/
        if let url = Bundle.main.url(forResource: "OpenNSFW", withExtension: "mlmodelc") {
            return url
        }

        // 2. Next to the executable (SwiftPM build output)
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let candidate = execDir.appendingPathComponent("ScreenGuard_ScreenGuard.bundle/OpenNSFW.mlmodelc")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        // 3. Source tree (development)
        let srcPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/OpenNSFW.mlmodelc")
        if FileManager.default.fileExists(atPath: srcPath.path) {
            return srcPath
        }

        return nil
    }

    func analyze(cgImage: CGImage) -> Bool {
        guard let model = visionModel else {
            sgLog.error("NSFW model not available")
            return false
        }

        var isNSFW = false
        let semaphore = DispatchSemaphore(value: 0)

        let request = VNCoreMLRequest(model: model) { request, error in
            defer { semaphore.signal() }

            if let error = error {
                sgLog.error("Vision request error: \(error.localizedDescription, privacy: .public)")
                return
            }

            guard let results = request.results as? [VNClassificationObservation] else { return }

            for result in results {
                sgLog.notice("\(result.identifier, privacy: .public): \(String(format: "%.1f%%", result.confidence * 100), privacy: .public)")
            }

            if let nsfwResult = results.first(where: { $0.identifier == "NSFW" }) {
                isNSFW = nsfwResult.confidence > self.threshold
            }
        }

        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
            semaphore.wait()
        } catch {
            sgLog.error("Image analysis failed: \(error.localizedDescription, privacy: .public)")
        }

        return isNSFW
    }
}
