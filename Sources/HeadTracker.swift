import AVFoundation
import QuartzCore
import Vision

/// One-shot head-position measurement, triggered by the user's Calibrate
/// click: the camera runs for a moment, the viewer's eye position is frozen
/// in 3D space, and the camera is turned off again. The frozen pose drives
/// every fold until the user clicks again. Frames are processed in memory and
/// discarded — never saved or sent.
final class HeadTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let queue = DispatchQueue(label: "local.macbookduo.head", qos: .userInitiated)
    private let lock = NSLock()
    private var lidAngle: Double?
    private var session: AVCaptureSession?
    private var loading = false
    private var screenHeightMeters = 0.3
    private var metrics = LidMetrics.standard
    private var samples: [EyePose] = []
    private var completion: ((EyePose?) -> Void)?
    private var timeoutItem: DispatchWorkItem?

    /// macOS does not expose the camera's field of view, so the face-size to
    /// distance step assumes a typical FaceTime-camera lens. The distance is
    /// therefore approximate; the angular offsets are genuinely measured.
    private static let assumedHorizontalFOV = 70.0
    private static let measurementTime: TimeInterval = 1.5
    private static let measurementsNeeded = 5

    /// The lid angle comes from the sensor queue; the tracker needs it to
    /// rotate the camera-frame measurement into the world frame at the
    /// moment of the click.
    func setLidAngle(_ angle: Double?) {
        lock.lock()
        lidAngle = angle
        lock.unlock()
    }

    /// Measures once and reports on the main thread. The camera starts for
    /// the measurement and stops as soon as it finishes.
    func measure(screenHeightMeters: Double, metrics: LidMetrics,
                 completion: @escaping (EyePose?) -> Void) {
        self.screenHeightMeters = screenHeightMeters.isFinite && screenHeightMeters > 0.05 ? screenHeightMeters : 0.3
        self.metrics = metrics
        queue.async {
            guard self.completion == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.completion = completion
            self.samples = []
            self.ensureRunning()
            self.timeoutItem?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.finish() }
            self.timeoutItem = item
            self.queue.asyncAfter(deadline: .now() + Self.measurementTime, execute: item)
        }
    }

    private func ensureRunning() {
        guard session == nil, !loading else { return }
        loading = true
        AVCaptureDevice.requestAccess(for: .video) { granted in
            self.queue.async {
                defer { self.loading = false }
                guard granted else {
                    self.finish()
                    return
                }
                // The measurement can time out (or be cancelled) while the
                // permission prompt is open. Without a live consumer the
                // camera would run with no timeout to stop it.
                guard self.completion != nil else { return }
                self.startSession()
            }
        }
    }

    private func startSession() {
        guard session == nil, completion != nil else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        let capture = AVCaptureSession()
        capture.sessionPreset = .vga640x480
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        capture.beginConfiguration()
        guard capture.canAddInput(input), capture.canAddOutput(output) else {
            capture.commitConfiguration()
            return
        }
        capture.addInput(input)
        capture.addOutput(output)
        capture.commitConfiguration()
        session = capture
        capture.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard session != nil, completion != nil, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        let angle = lidAngle
        lock.unlock()
        guard let angle, angle.isFinite else { return }
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // A failed detection is just a skipped sample; the timeout ends
            // the measurement if no frame succeeds.
            return
        }
        guard let face = request.results?.first else { return }
        // The eyes are the point the projection cares about; the face-box
        // centre sits near the nose and biases the measured height low.
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let eyeCenter = Self.eyeMidpoint(of: face.landmarks)
        guard let cameraPose = FaceGeometry.estimate(
                faceBox: face.boundingBox,
                eyeCenter: eyeCenter,
                frameWidth: Double(size.width),
                frameHeight: Double(size.height),
                horizontalFOVDegrees: Self.assumedHorizontalFOV,
                screenHeightMeters: screenHeightMeters) else { return }
        samples.append(FaceGeometry.worldEye(camera: cameraPose, lidAngleDegrees: angle, metrics: metrics))
        if samples.count >= Self.measurementsNeeded { finish() }
    }

    /// Midpoint of the eye regions in normalized image coordinates (Vision's
    /// origin is bottom-left), or nil when Vision found no eye landmarks.
    private static func eyeMidpoint(of landmarks: VNFaceLandmarks2D?) -> CGPoint? {
        guard let landmarks else { return nil }
        func center(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let region else { return nil }
            let points = Array(region.normalizedPoints)
            guard !points.isEmpty else { return nil }
            let x = points.map { Double($0.x) }.reduce(0, +) / Double(points.count)
            let y = points.map { Double($0.y) }.reduce(0, +) / Double(points.count)
            return CGPoint(x: x, y: y)
        }
        switch (center(landmarks.leftEye), center(landmarks.rightEye)) {
        case let (left?, right?):
            return CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        case let (left?, nil): return left
        case let (nil, right?): return right
        default: return nil
        }
    }

    /// Freeze the averaged pose, stop the camera and report.
    private func finish() {
        timeoutItem?.cancel()
        timeoutItem = nil
        guard let handler = completion else { return }
        completion = nil
        let capture = session
        session = nil
        capture?.stopRunning()
        let poses = samples
        samples = []
        var pose: EyePose?
        if !poses.isEmpty {
            let count = Double(poses.count)
            let x = poses.reduce(0) { $0 + $1.x } / count
            let y = poses.reduce(0) { $0 + $1.y } / count
            let z = poses.reduce(0) { $0 + $1.z } / count
            pose = EyePose(x: x, y: y, z: z)
        }
        DispatchQueue.main.async { handler(pose) }
    }
}
