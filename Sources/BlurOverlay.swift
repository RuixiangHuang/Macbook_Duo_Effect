import AppKit
import ScreenCaptureKit
import CoreImage
import Metal
import MetalKit

/// Capture only replaces the latest buffer. MetalKit schedules smooth 60 Hz draws;
/// there is no per-frame CGImage allocation, CPU readback or main-queue image upload.
final class FrameRenderer: NSObject, SCStreamOutput, SCStreamDelegate, MTKViewDelegate {
    let queue = DispatchQueue(label: "local.macbookduo.frames", qos: .userInteractive)
    private let context: CIContext
    private let commands: MTLCommandQueue
    private let lock = NSLock()
    private let framesInFlight = DispatchSemaphore(value: 2)
    private var latest: CVPixelBuffer?
    private var radius = 0.0
    private var geometry = EffectGeometry.identity
    private var stopped = false
    private var presented = false
    private var motion = EffectMotion()
    private var lastFrameTime = 0.0
    private weak var view: MTKView?
    private let deliver: () -> Void
    private let fail: (LocalizedText) -> Void
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init(view: MTKView, device: MTLDevice, commands: MTLCommandQueue,
         deliver: @escaping () -> Void, fail: @escaping (LocalizedText) -> Void) {
        context = CIContext(mtlCommandQueue: commands, options: [.cacheIntermediates: false])
        self.commands = commands
        self.view = view
        self.deliver = deliver
        self.fail = fail
        super.init()
        view.delegate = self
        DebugLog.shared.log("renderer created drawable=\(Int(view.drawableSize.width))x\(Int(view.drawableSize.height))")
    }

    deinit { DebugLog.shared.log("renderer released") }

    func setEffect(radius value: Double, geometry: EffectGeometry) {
        lock.lock()
        self.radius = value
        self.geometry = geometry
        lock.unlock()
    }
    func start() {
        view?.isPaused = false
        view?.draw()
    }
    func stop() {
        DebugLog.shared.log("renderer stop requested")
        lock.lock()
        stopped = true
        latest = nil
        lock.unlock()
        view?.isPaused = true
        view?.delegate = nil
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return }
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        if status == .complete {
            latest = sampleBuffer.imageBuffer
            lock.unlock()
        } else if status == .blank || status == .suspended || status == .stopped {
            latest = nil
            lock.unlock()
            DispatchQueue.main.async { self.fail(LocalizedText(en: "Display capture paused; effect removed", zh: "显示画面已暂停；效果已移除")) }
        } else { lock.unlock() }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.fail(LocalizedText.system(error)) }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        lock.lock()
        let buffer = latest
        let targetRadius = radius
        let targetGeometry = geometry
        let active = !stopped
        lock.unlock()
        guard active, targetRadius > 0, let buffer,
              framesInFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = view.currentDrawable, let command = commands.makeCommandBuffer() else {
            framesInFlight.signal(); return
        }
        let now = CACurrentMediaTime()
        let elapsed = lastFrameTime == 0 ? 1.0 / 60 : min(0.1, now - lastFrameTime)
        lastFrameTime = now
        motion.advance(radius: targetRadius, geometry: targetGeometry, deltaTime: elapsed)
        autoreleasepool {
            let input = CIImage(cvPixelBuffer: buffer)
            let output = EffectProcessor.image(input, radius: motion.radius, geometry: motion.geometry)
            let bounds = CGRect(x: 0, y: 0, width: drawable.texture.width, height: drawable.texture.height)
            let scaled = EffectProcessor.metalImage(output, bounds: bounds)
            context.render(scaled, to: drawable.texture, commandBuffer: command, bounds: bounds, colorSpace: colorSpace)
            command.present(drawable)
            command.addCompletedHandler { [weak self, buffer, budget = framesInFlight] finished in
                // Retain the CVPixelBuffer until the GPU has finished consuming it.
                _ = buffer
                // The semaphore is captured strongly, not reached through self.
                // clear() can release the renderer while a frame is still on the
                // GPU; releasing the semaphore with a count outstanding makes
                // libdispatch trap the whole process.
                budget.signal()
                // Only anomalies: a per-frame line at 60fps buries the lifecycle
                // events this log exists for.
                if finished.status != .completed {
                    DebugLog.shared.log("frame ended status=\(finished.status.rawValue) error=\(finished.error?.localizedDescription ?? "none")")
                }
                guard let self else { return }
                self.lock.lock()
                let shouldDeliver = !self.stopped && !self.presented && finished.status == .completed
                if shouldDeliver { self.presented = true }
                let shouldFail = !self.stopped && finished.status == .error
                self.lock.unlock()
                if shouldDeliver { DispatchQueue.main.async { self.deliver() } }
                if shouldFail { DispatchQueue.main.async { self.fail(LocalizedText(en: "GPU rendering failed; please retry", zh: "GPU 渲染失败，请重试")) } }
            }
            command.commit()
        }
    }
}

/// Public methods are called only from the main thread.
final class BlurOverlay: NSObject {
    private var window: NSWindow?
    private var stream: SCStream?
    private var renderer: FrameRenderer?
    private var starting = false
    private var generation = 0
    private var radius = 0.0
    private var geometry = EffectGeometry.identity
    private var lastUpdate = Date.distantPast
    private var backingScale = 1.0
    private var watchdog: Timer?
    var onError: ((LocalizedText) -> Void)?
    var onFirstFrame: (() -> Void)?
    var isVisible: Bool { window?.isVisible == true && (window?.alphaValue ?? 0) > 0 }

    static var builtInScreen: NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }
    }

    func update(radius value: Double, geometry: EffectGeometry = .identity) {
        self.geometry = geometry
        lastUpdate = Date()
        radius = value
        guard value > 0 else { clear(); return }
        renderer?.setEffect(radius: value * backingScale, geometry: geometry)
        guard !starting, stream == nil else { return }
        starting = true
        generation += 1
        let ticket = generation
        Task { @MainActor in
            do {
                guard let screen = Self.builtInScreen,
                      let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                    throw OverlayFailure(LocalizedText(en: "No built-in display found", zh: "未找到内置显示器"))
                }
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard ticket == self.generation, self.radius > 0 else { return }
                guard let display = content.displays.first(where: { $0.displayID == number.uint32Value }),
                      let ownApp = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else {
                    throw OverlayFailure(LocalizedText(en: "Could not establish a safe display capture; reopen the app", zh: "无法建立安全的显示捕获；请重新打开应用"))
                }
                let filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
                if #available(macOS 14.2, *) { filter.includeMenuBar = true }
                let config = SCStreamConfiguration()
                // Preserve Retina detail even when the blur radius approaches zero.
                let scale = screen.backingScaleFactor
                self.backingScale = scale
                config.width = Int(screen.frame.width * scale)
                config.height = Int(screen.frame.height * scale)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.queueDepth = 3
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false
                config.capturesAudio = false
                config.colorSpaceName = CGColorSpace.sRGB
                let panel = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                panel.ignoresMouseEvents = true
                // Cover both the menu titles and system status items. Mouse events still pass through.
                panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                panel.isReleasedWhenClosed = false
                guard let device = MTLCreateSystemDefaultDevice(), let commands = device.makeCommandQueue() else {
                    throw OverlayFailure(LocalizedText(en: "Metal rendering unavailable", zh: "Metal 渲染不可用"))
                }
                let metalView = MTKView(frame: CGRect(origin: .zero, size: screen.frame.size), device: device)
                metalView.framebufferOnly = false
                metalView.colorPixelFormat = .bgra8Unorm
                metalView.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
                metalView.preferredFramesPerSecond = 60
                metalView.isPaused = true
                metalView.enableSetNeedsDisplay = false
                metalView.autoResizeDrawable = false
                metalView.drawableSize = CGSize(width: config.width, height: config.height)
                panel.contentView = metalView
                panel.alphaValue = 0
                self.window = panel
                panel.orderFrontRegardless()
                let receiver = FrameRenderer(view: metalView, device: device, commands: commands, deliver: { [weak self] in
                    guard let self, ticket == self.generation, self.radius > 0 else { return }
                    self.window?.alphaValue = 1
                    self.onFirstFrame?()
                }, fail: { [weak self] error in
                    guard let self, ticket == self.generation else { return }
                    self.clear()
                    self.onError?(error)
                })
                self.renderer = receiver
                receiver.setEffect(radius: self.radius * scale, geometry: self.geometry)
                let capture = SCStream(filter: filter, configuration: config, delegate: receiver)
                try capture.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: receiver.queue)
                self.stream = capture
                try await capture.startCapture()
                guard ticket == self.generation else {
                    receiver.stop()
                    try? await capture.stopCapture()
                    return
                }
                self.starting = false
                receiver.start()
                self.startWatchdog()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, ticket == self.generation, !self.isVisible else { return }
                    self.clear()
                    self.onError?(LocalizedText(en: "No screen frames received; check Screen Recording permission and retry", zh: "未收到屏幕画面，请检查屏幕录制权限后重试"))
                }
            } catch {
                guard ticket == self.generation else { return }
                self.clear()
                let failure = (error as? OverlayFailure)?.text ?? LocalizedText.system(error)
                DebugLog.shared.log("capture start failed: \(failure.en)")
                self.onError?(failure)
            }
        }
    }

    private func startWatchdog() {
        watchdog = Timer(timeInterval: 0.5, target: self, selector: #selector(checkSensorFreshness), userInfo: nil, repeats: true)
        RunLoop.main.add(watchdog!, forMode: .common)
    }

    @objc private func checkSensorFreshness() {
        if Date().timeIntervalSince(lastUpdate) > 1.5 { clear() }
    }

    func clear() {
        if window != nil || renderer != nil || stream != nil {
            DebugLog.shared.log("overlay clear window=\(window != nil) renderer=\(renderer != nil) stream=\(stream != nil)")
        }
        radius = 0
        generation += 1
        starting = false
        watchdog?.invalidate()
        watchdog = nil
        window?.orderOut(nil)
        window?.contentView?.layer?.contents = nil
        window = nil
        renderer?.stop()
        renderer = nil
        if let previous = stream {
            stream = nil
            Task { try? await previous.stopCapture() }
        }
    }
}
