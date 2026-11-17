import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import Vision

/// Samples the camera in short low-rate bursts during breaks and reports blinks.
/// Frames stay in memory and are discarded; only numbers leave this class.
final class CameraTracker: NSObject {
    struct Sample {
        let frames: Int
        let faceFrames: Int
        let blinks: Int
    }

    var onBlink: (@MainActor () -> Void)?
    var onActive: (@MainActor (Bool) -> Void)?
    var onStatus: (@MainActor (String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "eyerule.camera.session")
    private let frameQueue = DispatchQueue(label: "eyerule.camera.frames")
    private let stateLock = NSLock()
    private let detector = BlinkDetector()

    private var configured = false
    private var acceptFrames = false
    private var lastProcessed = -1.0
    private let targetFPS = 10.0
    private var frames = 0
    private var faceFrames = 0
    private var blinkCount = 0

    func prepare(completion: @escaping @MainActor (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(true) } }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { MainActor.assumeIsolated { completion(granted) } }
            }
        default:
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(false) } }
        }
    }

    func start() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            deliverStatus("Camera access denied. Enable it in System Settings.")
            return
        }
        detector.reset()
        stateLock.lock()
        frames = 0
        faceFrames = 0
        blinkCount = 0
        stateLock.unlock()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.configureIfNeeded() else { return }
            self.frameQueue.async { self.lastProcessed = -1 }
            self.setAcceptingFrames(true)
            if !self.session.isRunning {
                self.session.startRunning()
            }
            self.deliverActive(true)
        }
    }

    func stop(completion: (@MainActor (Sample) -> Void)? = nil) {
        setAcceptingFrames(false)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.stateLock.lock()
            let sample = Sample(frames: self.frames,
                                faceFrames: self.faceFrames,
                                blinks: self.blinkCount)
            self.stateLock.unlock()
            self.deliverActive(false)
            if let completion {
                DispatchQueue.main.async { MainActor.assumeIsolated { completion(sample) } }
            }
        }
    }

    private func setAcceptingFrames(_ accepting: Bool) {
        stateLock.lock()
        acceptFrames = accepting
        stateLock.unlock()
    }

    private func acceptsFrames() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return acceptFrames
    }

    private func configureIfNeeded() -> Bool {
        guard !configured else { return true }
        guard let device = AVCaptureDevice.default(for: .video) else {
            deliverStatus("No camera found.")
            return false
        }

        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            deliverStatus("Could not open the camera.")
            return false
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.setSampleBufferDelegate(self, queue: frameQueue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            deliverStatus("Could not open the camera.")
            return false
        }
        session.addOutput(output)
        session.commitConfiguration()
        configured = true
        return true
    }

    private func eyeRatio(_ region: VNFaceLandmarkRegion2D?) -> Double? {
        guard let points = region?.normalizedPoints, points.count >= 4 else { return nil }
        let xs = points.map { Double($0.x) }
        let ys = points.map { Double($0.y) }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(), maxX > minX else { return nil }
        return (maxY - minY) / (maxX - minX)
    }

    private func deliverBlink() {
        let callback = onBlink
        DispatchQueue.main.async { MainActor.assumeIsolated { callback?() } }
    }

    private func deliverActive(_ active: Bool) {
        let callback = onActive
        DispatchQueue.main.async { MainActor.assumeIsolated { callback?(active) } }
    }

    private func deliverStatus(_ text: String) {
        let callback = onStatus
        DispatchQueue.main.async { MainActor.assumeIsolated { callback?(text) } }
    }
}

extension CameraTracker: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard acceptsFrames() else { return }

        let now = CACurrentMediaTime()
        if lastProcessed >= 0 && now - lastProcessed < 1.0 / targetFPS { return }
        lastProcessed = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceLandmarksRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
        } catch {
            return
        }

        let face = (request.results ?? []).max {
            $0.boundingBox.width * $0.boundingBox.height <
                $1.boundingBox.width * $1.boundingBox.height
        }
        guard let face else {
            detector.faceLost()
            stateLock.lock()
            frames += 1
            stateLock.unlock()
            return
        }
        stateLock.lock()
        frames += 1
        faceFrames += 1
        stateLock.unlock()

        let left = eyeRatio(face.landmarks?.leftEye)
        let right = eyeRatio(face.landmarks?.rightEye)
        let ear: Double?
        switch (left, right) {
        case let (l?, r?): ear = (l + r) / 2
        case let (l?, nil): ear = l
        case let (nil, r?): ear = r
        default: ear = nil
        }

        if detector.update(ear: ear) {
            stateLock.lock()
            blinkCount += 1
            stateLock.unlock()
            deliverBlink()
        }
    }
}

/// Adaptive eye-aspect-ratio thresholding with hysteresis.
/// The first frames calibrate an open-eye baseline; a rise back above the high
/// threshold after dipping below the low one counts as one blink.
final class BlinkDetector {
    private let lock = NSLock()
    private var baseline: [Double] = []
    private var low = 0.16
    private var high = 0.22
    private var calibrated = false
    private var closed = false

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        baseline.removeAll()
        low = 0.16
        high = 0.22
        calibrated = false
        closed = false
    }

    func faceLost() {
        lock.lock()
        defer { lock.unlock() }
        closed = false
    }

    func update(ear: Double?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let ear else {
            closed = false
            return false
        }

        if !calibrated {
            baseline.append(ear)
            guard baseline.count >= 10 else { return false }
            let sorted = baseline.sorted()
            let median = sorted[sorted.count / 2]
            low = max(0.08, median * 0.6)
            high = max(low + 0.03, median * 0.75)
            calibrated = true
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
