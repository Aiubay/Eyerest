import AppKit
import AVFoundation
import CoreMedia
import Foundation
import QuartzCore
import Vision

// Usage: CameraSpike [log-path] [seconds] [fps]

let arguments = CommandLine.arguments
let defaultLog = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/CameraSpike.log").path
let logPath = arguments.count > 1 ? arguments[1] : defaultLog
let runSeconds = arguments.count > 2 ? (Double(arguments[2]) ?? 60) : 60
let targetFPS = arguments.count > 3 ? (Double(arguments[3]) ?? 5) : 5

var logHandle: FileHandle?
let logLock = NSLock()

func log(_ message: String) {
    let line = message + "\n"
    logLock.lock()
    defer { logLock.unlock() }
    FileHandle.standardOutput.write(Data(line.utf8))
    logHandle?.write(Data(line.utf8))
}

func openLog() -> Bool {
    FileManager.default.createFile(atPath: logPath, contents: nil)
    logHandle = FileHandle(forWritingAtPath: logPath)
    return logHandle != nil
}

guard openLog() else {
    FileHandle.standardError.write(Data("Cannot open log file at \(logPath)\n".utf8))
    exit(1)
}

func eyeRatio(_ region: VNFaceLandmarkRegion2D?) -> Double? {
    guard let points = region?.normalizedPoints, points.count >= 4 else { return nil }
    let xs = points.map { Double($0.x) }
    let ys = points.map { Double($0.y) }
    guard let minX = xs.min(), let maxX = xs.max(),
          let minY = ys.min(), let maxY = ys.max(), maxX > minX else { return nil }
    return (maxY - minY) / (maxX - minX)
}

final class Stats {
    private let lock = NSLock()
    private var samples = 0
    private var faceFrames = 0
    private var blinks = 0
    private var earSum = 0.0
    private var earCount = 0
    private var visionMS: [Double] = []
    private var faceWidthSum = 0.0

    func record(face: Bool, ear: Double?, visionMS: Double, faceWidth: Double) {
        lock.lock()
        defer { lock.unlock() }
        samples += 1
        self.visionMS.append(visionMS)
        if face {
            faceFrames += 1
            faceWidthSum += faceWidth
        }
        if let ear {
            earSum += ear
            earCount += 1
        }
    }

    func countBlink() {
        lock.lock()
        blinks += 1
        lock.unlock()
    }

    var blinkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return blinks
    }

    func summary(seconds: Double) -> String {
        lock.lock()
        defer { lock.unlock() }
        guard samples > 0 else { return "SUMMARY: no frames processed" }
        let sorted = visionMS.sorted()
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let avgMS = visionMS.reduce(0, +) / Double(visionMS.count)
        let facePct = Double(faceFrames) / Double(samples) * 100
        let avgEar = earCount > 0 ? earSum / Double(earCount) : 0
        let perMinute = Double(blinks) / seconds * 60
        let avgFaceWidth = faceFrames > 0 ? faceWidthSum / Double(faceFrames) * 100 : 0
        return String(
            format: "SUMMARY: samples=%d over %.0fs (%.1f fps) face=%.0f%% blinks=%d (%.1f/min) avgEAR=%.3f avgFaceWidth=%.0f%% visionAvg=%.1fms visionP95=%.1fms",
            samples, seconds, Double(samples) / seconds, facePct,
            blinks, perMinute, avgEar, avgFaceWidth, avgMS, p95
        )
    }
}

final class BlinkDetector {
    private var baselineSamples: [Double] = []
    private var closed = false
    private var low = 0.16
    private var high = 0.22
    private var calibrated = false

    func update(ear: Double?) -> Bool {
        guard let ear else { return false }
        baselineSamples.append(ear)

        if !calibrated {
            if baselineSamples.count >= 15 {
                let sorted = baselineSamples.sorted()
                let median = sorted[sorted.count / 2]
                low = max(0.08, median * 0.6)
                high = max(low + 0.03, median * 0.75)
                calibrated = true
                log(String(format: "baseline open-eye ratio %.3f -> thresholds %.3f / %.3f", median, low, high))
            }
            return false
        }

        if !closed && ear < low {
            closed = true
        } else if closed && ear > high {
            closed = false
            return true
        }
        return false
    }
}

final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let stats = Stats()
    private let detector = BlinkDetector()
    private let targetFPS: Double
    private let start = CACurrentMediaTime()
    private var lastProcessed = -1.0

    init(targetFPS: Double) {
        self.targetFPS = targetFPS
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CACurrentMediaTime()
        if lastProcessed >= 0 && now - lastProcessed < 1.0 / targetFPS { return }
        lastProcessed = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)

        let visionStart = CACurrentMediaTime()
        do {
            try handler.perform([request])
        } catch {
            log("Vision error: \(error.localizedDescription)")
            return
        }
        let ms = (CACurrentMediaTime() - visionStart) * 1000
        let elapsed = now - start

        let faces = (request.results ?? []).sorted {
            $0.boundingBox.width * $0.boundingBox.height >
                $1.boundingBox.width * $1.boundingBox.height
        }

        if let face = faces.first {
            let left = eyeRatio(face.landmarks?.leftEye)
            let right = eyeRatio(face.landmarks?.rightEye)
            let ear: Double?
            switch (left, right) {
            case let (l?, r?): ear = (l + r) / 2
            case let (l?, nil): ear = l
            case let (nil, r?): ear = r
            default: ear = nil
            }
            let blink = detector.update(ear: ear)
            stats.record(face: true, ear: ear, visionMS: ms, faceWidth: Double(face.boundingBox.width))
            if blink {
                stats.countBlink()
                log(String(format: "BLINK #%d at t=%.1fs ear=%.3f", stats.blinkCount, elapsed, ear ?? 0))
            }
            log(String(format: "t=%5.1f face=1 ear=%@ ms=%.1f",
                       elapsed,
                       ear.map { String(format: "%.3f", $0) } ?? " - ",
                       ms))
        } else {
            stats.record(face: false, ear: nil, visionMS: ms, faceWidth: 0)
            log(String(format: "t=%5.1f face=0 ms=%.1f", elapsed, ms))
        }
    }
}

log("CameraSpike start \(Date()) log=\(logPath) seconds=\(runSeconds) targetFPS=\(targetFPS)")
log("Numbers only in this log: no frames are saved or sent.")

_ = NSApplication.shared

let authorization = AVCaptureDevice.authorizationStatus(for: .video)
if authorization == .notDetermined {
    log("Requesting camera permission. Approve the macOS dialog for CameraSpike.")
    let semaphore = DispatchSemaphore(value: 0)
    AVCaptureDevice.requestAccess(for: .video) { granted in
        log("Permission \(granted ? "granted" : "denied")")
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 120)
}

guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
    log("Camera not authorized. Enable CameraSpike under System Settings > Privacy & Security > Camera, then rerun.")
    logHandle?.synchronizeFile()
    exit(2)
}

let session = AVCaptureSession()
session.sessionPreset = .vga640x480

guard let device = AVCaptureDevice.default(for: .video) else {
    log("No camera device found.")
    logHandle?.synchronizeFile()
    exit(3)
}

guard let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input) else {
    log("Cannot open camera input.")
    logHandle?.synchronizeFile()
    exit(4)
}
session.addInput(input)
log("Camera: \(device.localizedName)")

let output = AVCaptureVideoDataOutput()
output.alwaysDiscardsLateVideoFrames = true
output.videoSettings = [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
]
let processor = FrameProcessor(targetFPS: targetFPS)
output.setSampleBufferDelegate(processor, queue: DispatchQueue(label: "camera.frames"))

guard session.canAddOutput(output) else {
    log("Cannot add video output.")
    logHandle?.synchronizeFile()
    exit(5)
}
session.addOutput(output)

let sessionQueue = DispatchQueue(label: "camera.session")
sessionQueue.async { session.startRunning() }

DispatchQueue.global().asyncAfter(deadline: .now() + runSeconds) {
    sessionQueue.sync { session.stopRunning() }
    log(processor.stats.summary(seconds: runSeconds))
    log("CameraSpike done")
    logHandle?.synchronizeFile()
    exit(0)
}

dispatchMain()
