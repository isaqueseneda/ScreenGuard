import CoreML
import Vision
import AppKit

/// Uses Yahoo's Open NSFW CoreML model for instant NSFW detection
final class ContentAnalyzer {
    static let shared = ContentAnalyzer()

    private var visionModel: VNCoreMLModel?
    private let threshold: Float = 0.75
    private let requiredConsecutive = 2
    private var consecutiveCount = 0

    var isModelLoaded: Bool { visionModel != nil }
    private(set) var lastNSFWScore: Float = 0

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

    /// Fast pre-filter: downsamples to 16x16 and checks color saturation.
    /// Text-heavy screens (terminals, IDEs, docs) are almost entirely desaturated
    /// and consistently cause false positives in the NSFW model.
    private func isLikelyTextScreen(_ cgImage: CGImage) -> Bool {
        let sampleSize = 16
        guard let context = CGContext(
            data: nil,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        guard let data = context.data else { return false }
        let pixels = data.assumingMemoryBound(to: UInt8.self)

        var lowSatCount = 0
        let totalPixels = sampleSize * sampleSize

        for i in 0..<totalPixels {
            let offset = i * 4
            let r = Float(pixels[offset]) / 255.0
            let g = Float(pixels[offset + 1]) / 255.0
            let b = Float(pixels[offset + 2]) / 255.0

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0

            if saturation < 0.15 {
                lowSatCount += 1
            }
        }

        let lowSatRatio = Float(lowSatCount) / Float(totalPixels)
        let isText = lowSatRatio > 0.85
        sgLog.notice("Saturation pre-filter: \(String(format: "%.0f%%", lowSatRatio * 100), privacy: .public) low-sat → \(isText ? "skip (text screen)" : "analyze", privacy: .public)")
        return isText
    }

    func analyze(cgImage: CGImage) -> Bool {
        // Skip NSFW model entirely for text-heavy screens (terminals, IDEs, docs)
        if isLikelyTextScreen(cgImage) {
            lastNSFWScore = 0
            consecutiveCount = 0
            return false
        }

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
                self.lastNSFWScore = nsfwResult.confidence
                if nsfwResult.confidence > self.threshold {
                    self.consecutiveCount += 1
                    isNSFW = self.consecutiveCount >= self.requiredConsecutive
                } else {
                    self.consecutiveCount = 0
                }
            }
        }

        // centerCrop preserves aspect ratio — scaleFill distorted widescreen
        // screenshots into 224x224 squares, creating artifacts that the model
        // misinterpreted as NSFW content
        request.imageCropAndScaleOption = .centerCrop

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
