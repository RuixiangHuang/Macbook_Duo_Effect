import AppKit
import SwiftUI

final class AppModel: ObservableObject {
    @Published var angle: Double?
    @Published var sensorStatus = LocalizedText(en: "Connecting to sensor…", zh: "正在连接传感器…")
    @Published var permission = false
    @Published var error: LocalizedText?
    @Published var previewing = false
    @Published var radius = 0.0
    @Published var enabled = true {
        didSet { UserDefaults.standard.set(enabled, forKey: "enabled"); onChange?() }
    }
    @Published var threshold = 90.0 {
        didSet { UserDefaults.standard.set(threshold, forKey: "threshold"); onChange?() }
    }
    @Published var maximum = 32.0 {
        didSet { UserDefaults.standard.set(maximum, forKey: "maximum"); onChange?() }
    }
    @Published var perspective = 1.0 {
        didSet { UserDefaults.standard.set(perspective, forKey: "perspective"); onChange?() }
    }
    @Published var calibrating = false
    @Published var eyeCalibrated = false
    @Published var eyeCentered = false
    @Published var autoCalibrate = false {
        didSet { UserDefaults.standard.set(autoCalibrate, forKey: "autoCalibrate") }
    }
    /// Lid offsets in millimetres. The preset comes from Apple's published
    /// dimensions; "use detected" keeps it, manual values override it when a
    /// lid has been measured directly.
    @Published var useDetectedLidGeometry = true {
        didSet { UserDefaults.standard.set(useDetectedLidGeometry, forKey: "useDetectedLidGeometry"); onChange?() }
    }
    @Published var lidHingeDropMM = LidGeometry.hingeDropMillimetres {
        didSet { UserDefaults.standard.set(lidHingeDropMM, forKey: "lidHingeDropMM"); onChange?() }
    }
    @Published var lidStandoffMM = LidGeometry.standoffMillimetres {
        didSet { UserDefaults.standard.set(lidStandoffMM, forKey: "lidStandoffMM"); onChange?() }
    }
    @Published var lidCameraInsetMM = LidGeometry.cameraInsetMillimetres {
        didSet { UserDefaults.standard.set(lidCameraInsetMM, forKey: "lidCameraInsetMM"); onChange?() }
    }
    @Published var lidCameraRecessMM = LidGeometry.cameraRecessMillimetres {
        didSet { UserDefaults.standard.set(lidCameraRecessMM, forKey: "lidCameraRecessMM"); onChange?() }
    }
    /// Shown in settings so the preset's provenance is visible.
    let detectedModelName = MachineModel.name(for: MachineModel.identifier)
    /// The offsets the projection actually uses, converted with the measured
    /// active height of this panel.
    func lidMetrics(screenHeightMillimetres: Double) -> LidMetrics {
        if useDetectedLidGeometry {
            return LidMetrics(hingeDropMM: LidGeometry.hingeDropMillimetres,
                              standoffMM: LidGeometry.standoffMillimetres,
                              cameraInsetMM: LidGeometry.cameraInsetMillimetres,
                              cameraRecessMM: LidGeometry.cameraRecessMillimetres,
                              screenHeightMillimetres: screenHeightMillimetres)
        }
        return LidMetrics(hingeDropMM: lidHingeDropMM, standoffMM: lidStandoffMM,
                          cameraInsetMM: lidCameraInsetMM, cameraRecessMM: lidCameraRecessMM,
                          screenHeightMillimetres: screenHeightMillimetres)
    }
    /// Measured (or nominal) viewer eye position driving the 3D projection.
    var eyePose = EyePose.nominal
    var eyeStatusText: String {
        if calibrating { return t("Looking for your face…", "正在寻找面部…") }
        if eyeCalibrated {
            return t("Your position is frozen from this seat. Click Calibrate again if you move.",
                     "已冻结当前座位的位置。换位置后请再次校准。")
        }
        if eyeCentered {
            return t("Using a centered viewer, as chosen. Calibrate to freeze your actual seat instead.",
                     "正在使用居中观看位置（已选择）。点击“校准”可改为冻结实际座位。")
        }
        return t("Centered viewer assumed (about 50 cm). Sit where you usually watch and click Calibrate to freeze your position.",
                 "默认居中观看（约 50 厘米）。请坐到常坐的位置后点击“校准”以冻结观看位置。")
    }
    var onChange: (() -> Void)?
    var requestPermission: (() -> Void)?
    var preview: (() -> Void)?
    var retry: (() -> Void)?
    var quit: (() -> Void)?
    var calibrateEye: (() -> Void)?
    var assumeCentered: (() -> Void)?
    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["enabled": true, "threshold": 90.0, "maximum": 32.0, "perspective": 1.0,
                                     "eyeX": 0.0, "eyeY": 1.3, "eyeZ": 1.6,
                                     "eyeCalibrated": false, "eyeCentered": false, "autoCalibrate": false,
                                     "useDetectedLidGeometry": true,
                                     "lidHingeDropMM": LidGeometry.hingeDropMillimetres,
                                     "lidStandoffMM": LidGeometry.standoffMillimetres,
                                     "lidCameraInsetMM": LidGeometry.cameraInsetMillimetres,
                                     "lidCameraRecessMM": LidGeometry.cameraRecessMillimetres])
        enabled = defaults.bool(forKey: "enabled")
        let x = defaults.double(forKey: "threshold")
        threshold = x.isFinite ? min(140, max(10, x)) : 90
        let blur = defaults.double(forKey: "maximum")
        maximum = blur.isFinite ? min(60, max(1, blur)) : 32
        let depth = defaults.double(forKey: "perspective")
        perspective = depth.isFinite ? min(1, max(0, depth)) : 1
        let ex = defaults.double(forKey: "eyeX")
        var ey = defaults.double(forKey: "eyeY")
        let ez = defaults.double(forKey: "eyeZ")
        // Older builds stored the centred pose with the eye level with the
        // hinge, which never hides the picture's top; migrate it to the
        // seated height.
        if ey == 0, defaults.bool(forKey: "eyeCentered") { ey = 1.3 }
        if ex.isFinite, ey.isFinite, ez.isFinite, ez > 0.2 {
            eyePose = EyePose(x: ex, y: ey, z: ez)
        }
        eyeCalibrated = defaults.bool(forKey: "eyeCalibrated")
        eyeCentered = defaults.bool(forKey: "eyeCentered")
        autoCalibrate = defaults.bool(forKey: "autoCalibrate")
        useDetectedLidGeometry = defaults.bool(forKey: "useDetectedLidGeometry")
        let hingeMM = defaults.double(forKey: "lidHingeDropMM")
        if hingeMM.isFinite { lidHingeDropMM = min(20, max(0, hingeMM)) }
        let standoffMM = defaults.double(forKey: "lidStandoffMM")
        if standoffMM.isFinite { lidStandoffMM = min(20, max(0, standoffMM)) }
        let insetMM = defaults.double(forKey: "lidCameraInsetMM")
        if insetMM.isFinite { lidCameraInsetMM = min(30, max(0, insetMM)) }
        let recessMM = defaults.double(forKey: "lidCameraRecessMM")
        if recessMM.isFinite { lidCameraRecessMM = min(20, max(0, recessMM)) }
    }
    var stateText: String {
        if !enabled { return t("Effect paused", "效果已暂停") }
        if !permission { return t("Waiting for Screen Recording permission", "等待屏幕录制授权") }
        if error != nil { return t("Effect paused · retry needed", "效果已暂停 · 需要重试") }
        if angle == nil { return t("Waiting for the lid angle sensor", "等待角度传感器") }
        if previewing { return t("Previewing · restores in 4s", "正在预览 · 4 秒后自动恢复") }
        return radius > 0 ? t("Perspective · fade · blur active", "透视 · 淡出 · 毛玻璃生效中")
                          : t("Screen is clear", "屏幕清晰")
    }
}

final class AppController: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let sensor = LidSensor()
    private let sensorQueue = DispatchQueue(label: "local.macbookduo.sensor", qos: .userInitiated)
    private var angleFilter = AngleFilter()
    private var sensorTimer: DispatchSourceTimer?
    private var permissionTimer: Timer?
    private let overlay = BlurOverlay()
    private var statusItem: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var settingsItem: NSMenuItem!
    private var quitItem: NSMenuItem!
    private var revealItem: NSMenuItem!
    private var angleItem: NSMenuItem!
    private var settings: NSWindow?
    private var suspensionReasons = Set<String>()
    private var sleeping: Bool { !suspensionReasons.isEmpty }
    private var previewDeadline: Date?
    private var observers: [NSObjectProtocol] = []
    private var shuttingDown = false
    private var lastEffectActive = false
    /// Degrees above the clear threshold where capture warms up, so the fold
    /// starts on live frames instead of a cold-capture pop-in.
    private let armBand = 15.0
    private let headTracker = HeadTracker()
    /// Set while the lid is below 40°, consumed by the first reopening past
    /// 75° so a gradual reopen still counts as one closed session.
    private var lidClosedSinceReopen = false
    private var reopenCalibrationTimer: DispatchWorkItem?
    private var reopenCalibrated = false
    private var debugItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.shared.log("app launched")
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        model.permission = CGPreflightScreenCaptureAccess()
        model.onChange = { [weak self] in self?.apply() }
        model.requestPermission = { [weak self] in self?.authorize() }
        model.calibrateEye = { [weak self] in self?.calibrateEye() }
        model.assumeCentered = { [weak self] in self?.assumeCentered() }
        model.preview = { [weak self] in self?.preview() }
        model.retry = { [weak self] in
            self?.model.error = nil
            self?.model.permission = CGPreflightScreenCaptureAccess()
            self?.apply()
        }
        model.quit = { NSApp.terminate(nil) }
        Localization.shared.onChange = { [weak self] in self?.refreshMenuTitles() }
        overlay.onFirstFrame = { DebugLog.shared.log("first frame presented") }
        overlay.onError = { [weak self] message in
            DebugLog.shared.log("error surfaced: \(message.en)")
            self?.model.error = message
            self?.model.radius = 0
        }
        let timer = DispatchSource.makeTimerSource(queue: sensorQueue)
        // Poll at the panel's frame rate so ProMotion folds get a fresh
        // target every display frame; the filter below absorbs the sensor's
        // one-degree quantization.
        timer.schedule(deadline: .now(), repeating: 1.0 / 120.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // Smooth the quantized report on the sensor queue so the menu bar
            // readout and the effect both see a continuous angle.
            let angle = self.angleFilter.update(self.sensor.read())
            // Keep the tracker's lid angle live so a calibration straddling a
            // small lid movement still compensates for the camera's ride.
            self.headTracker.setLidAngle(angle)
            let status = self.sensor.status
            DispatchQueue.main.async {
                guard !self.shuttingDown else { return }
                if self.model.sensorStatus.en != status.en {
                    DebugLog.shared.log("sensor status: \(status.en)")
                }
                self.model.angle = angle
                self.model.sensorStatus = status
                self.trackReopenForAutoCalibration(angle)
                self.apply()
            }
        }
        sensorTimer = timer
        timer.resume()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let permission = CGPreflightScreenCaptureAccess()
            if self.model.permission != permission {
                DebugLog.shared.log("screen recording permission -> \(permission)")
                self.model.permission = permission
                self.apply()
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, "system"), (NSWorkspace.screensDidSleepNotification, "display"), (NSWorkspace.sessionDidResignActiveNotification, "session")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DebugLog.shared.log("suspend: \(reason)")
                self?.suspensionReasons.insert(reason)
                self?.cancelPreview()
                self?.overlay.clear()
                self?.model.radius = 0
            })
        }
        for (name, reason) in [(NSWorkspace.didWakeNotification, "system"), (NSWorkspace.screensDidWakeNotification, "display"), (NSWorkspace.sessionDidBecomeActiveNotification, "session")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DebugLog.shared.log("resume: \(reason)")
                self?.suspensionReasons.remove(reason)
                self?.model.error = nil
                self?.model.angle = nil
                self?.sensorQueue.async { self?.sensor.connect() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.overlay.clear()
            self?.model.error = nil
        })
        showSettings()
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Duo Effect")
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        angleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(angleItem)
        menu.addItem(.separator())
        settingsItem = NSMenuItem(title: "", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self; menu.addItem(settingsItem)
        pauseItem = NSMenuItem(title: "", action: #selector(toggle), keyEquivalent: "p")
        pauseItem.target = self; menu.addItem(pauseItem)
        menu.addItem(.separator())
        debugItem = NSMenuItem(title: "", action: #selector(toggleDebug), keyEquivalent: "")
        debugItem.target = self; menu.addItem(debugItem)
        let reveal = NSMenuItem(title: "", action: #selector(revealLog), keyEquivalent: "")
        reveal.target = self; menu.addItem(reveal)
        revealItem = reveal
        menu.addItem(.separator())
        quitItem = NSMenuItem(title: "", action: #selector(terminate), keyEquivalent: "q")
        quitItem.target = self; menu.addItem(quitItem)
        statusItem.menu = menu
        refreshMenuTitles()
    }

    /// Every status-item title is rebuilt here so a language switch updates them all.
    private func refreshMenuTitles() {
        let title = model.angle.map { String(format: " %.0f°", $0) } ?? " —°"
        if statusItem.button?.title != title { statusItem.button?.title = title }
        angleItem.title = t("Lid angle\(title) · threshold \(Int(model.threshold))°",
                            "开合角度\(title) · 阈值 \(Int(model.threshold))°")
        settingsItem.title = t("Duo Effect Settings…", "Duo Effect 设置…")
        pauseItem.title = model.enabled ? t("Pause Effect", "暂停效果") : t("Enable Effect", "启用效果")
        quitItem.title = t("Quit Duo Effect", "退出 Duo Effect")
        debugItem.title = DebugLog.shared.isEnabled ? t("Stop Debug Logging", "停止调试日志")
                                                    : t("Start Debug Logging", "开启调试日志")
        revealItem.title = t("Show Debug Log…", "显示调试日志…")
        revealItem.isHidden = !DebugLog.shared.isEnabled
    }

    @objc private func toggleDebug() {
        DebugLog.shared.setEnabled(!DebugLog.shared.isEnabled)
        refreshMenuTitles()
    }

    @objc private func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([DebugLog.shared.fileURL])
    }
    @objc private func toggle() { model.enabled.toggle() }
    @objc private func terminate() { NSApp.terminate(nil) }

    /// Opt-in: after the user reopens the lid and sits still for ten seconds,
    /// freeze a fresh position once per open session.
    private func trackReopenForAutoCalibration(_ angle: Double?) {
        guard let angle else { return }
        if angle < 40 {
            // Latch the closed part of the session; the reopen may pass
            // through the intermediate angles at any speed.
            lidClosedSinceReopen = true
            reopenCalibrated = false
            reopenCalibrationTimer?.cancel()
            reopenCalibrationTimer = nil
            return
        }
        guard lidClosedSinceReopen, angle > 75,
              !reopenCalibrated, model.autoCalibrate, model.enabled,
              reopenCalibrationTimer == nil else { return }
        lidClosedSinceReopen = false
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.shuttingDown else { return }
            self.reopenCalibrationTimer = nil
            guard self.model.autoCalibrate, !self.model.calibrating,
                  let current = self.model.angle, current > 60 else { return }
            self.reopenCalibrated = true
            DebugLog.shared.log("auto-calibrating ten seconds after reopen")
            self.calibrateEye()
        }
        reopenCalibrationTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
    }

    /// Explicit opt-in to the nominal centered viewer.
    private func assumeCentered() {
        model.eyePose = EyePose.nominal
        model.eyeCalibrated = false
        model.eyeCentered = true
        let defaults = UserDefaults.standard
        defaults.set(0.0, forKey: "eyeX")
        defaults.set(1.3, forKey: "eyeY")
        defaults.set(1.6, forKey: "eyeZ")
        defaults.set(false, forKey: "eyeCalibrated")
        defaults.set(true, forKey: "eyeCentered")
        DebugLog.shared.log("eye pose set to centered by user")
        apply()
    }

    /// Manual calibration: freezes the viewer's position in 3D space at the
    /// moment of the click. The camera runs only for this measurement and is
    /// off at all other times.
    private func calibrateEye() {
        guard !model.calibrating else { return }
        model.calibrating = true
        let screenHeight = Self.builtInScreenHeightMeters()
        headTracker.measure(screenHeightMeters: screenHeight,
                            metrics: model.lidMetrics(screenHeightMillimetres: screenHeight * 1000)) { [weak self] pose in
            guard let self else { return }
            self.model.calibrating = false
            if let pose {
                self.model.eyePose = pose
                self.model.eyeCalibrated = true
                self.model.eyeCentered = false
                let defaults = UserDefaults.standard
                defaults.set(pose.x, forKey: "eyeX")
                defaults.set(pose.y, forKey: "eyeY")
                defaults.set(pose.z, forKey: "eyeZ")
                defaults.set(true, forKey: "eyeCalibrated")
                defaults.set(false, forKey: "eyeCentered")
                DebugLog.shared.log(String(format: "eye pose calibrated x=%.2f y=%.2f z=%.2f",
                                           pose.x, pose.y, pose.z))
            } else {
                DebugLog.shared.log("eye pose calibration unavailable; keeping previous pose")
            }
            self.apply()
        }
    }

    private static func builtInScreenHeightMeters() -> Double {
        guard let screen = BlurOverlay.builtInScreen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 0.3
        }
        let height = Double(CGDisplayScreenSize(number.uint32Value).height) / 1000
        return height > 0.05 ? height : 0.3
    }

    private func apply() {
        guard !shuttingDown else { return }
        if let deadline = previewDeadline, Date() >= deadline { cancelPreview() }
        if !model.enabled { cancelPreview() }
        let angle = model.previewing ? model.threshold * 0.25 : model.angle
        let desired = EffectModel.radius(angle: angle, threshold: model.threshold, maximum: model.maximum,
                                         enabled: model.enabled && model.permission && !sleeping && model.error == nil)
        // The renderer interpolates all visual properties on its frame clock.
        model.radius = desired
        if (desired > 0) != lastEffectActive {
            lastEffectActive = desired > 0
            DebugLog.shared.log("effect \(lastEffectActive ? "on" : "off") angle=\(angle.map { String(format: "%.1f", $0) } ?? "nil") threshold=\(Int(model.threshold)) permission=\(model.permission) sleeping=\(sleeping)")
        }
        let armed = model.enabled && model.permission && !sleeping && model.error == nil
        let approaching = armed && !model.previewing
            && (model.angle.map { $0.isFinite && $0 < model.threshold + armBand } ?? false)
        let aspect = BlurOverlay.builtInScreen.map { Double($0.frame.width / $0.frame.height) } ?? 1.55
        let screenHeightMM = Self.builtInScreenHeightMeters() * 1000
        let metrics = model.lidMetrics(screenHeightMillimetres: screenHeightMM)
        overlay.update(radius: model.radius, geometry: EffectModel.geometry(angle: angle, threshold: model.threshold, strength: model.perspective, eye: model.eyePose, aspect: aspect, metrics: metrics), approaching: approaching)
        refreshMenuTitles()
    }

    private func authorize() {
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        model.permission = CGPreflightScreenCaptureAccess()
        model.error = nil
        apply()
    }
    private func preview() {
        guard model.permission, model.enabled else { return }
        if model.previewing { cancelPreview(); apply(); return }
        model.error = nil
        model.previewing = true
        previewDeadline = Date().addingTimeInterval(4)
        apply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, let deadline = self.previewDeadline, Date() >= deadline else { return }
            self.cancelPreview()
            self.apply()
        }
    }
    private func cancelPreview() { previewDeadline = nil; model.previewing = false }

    @objc func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 900),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Duo Effect"
            // A standard title bar keeps the content — including the enable
            // toggle — below the drag region. With a transparent title bar the
            // SwiftUI content sat under it and the toggle could not be clicked.
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = false
            window.isReleasedWhenClosed = false
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    // A Dock icon makes the settings window the app's only window, so closing it
    // must not end the effect; the status item stays the way to quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        DebugLog.shared.log("app terminating normally")
        shuttingDown = true
        permissionTimer?.invalidate()
        sensorTimer?.cancel()
        sensorQueue.sync { sensor.disconnect() }
        overlay.clear()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

private func lidField(_ title: String, value: Binding<Double>, accent: Color) -> some View {
    HStack(spacing: 6) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Spacer(minLength: 4)
        TextField("0", value: value, format: .number.precision(.fractionLength(1)))
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)
            .multilineTextAlignment(.trailing)
            .tint(accent)
        Text("mm").font(.caption2).foregroundStyle(.secondary)
    }
}

struct SettingsView: View {
    @State private var showLidAdvanced = false
    @ObservedObject var model: AppModel
    @ObservedObject private var localization = Localization.shared
    private let accent = Color(red: 0.45, green: 0.43, blue: 0.91)
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                Menu {
                    ForEach(Language.allCases, id: \.self) { language in
                        Button {
                            localization.language = language
                        } label: {
                            if localization.language == language {
                                Label(language.displayName, systemImage: "checkmark")
                            } else {
                                Text(language.displayName)
                            }
                        }
                    }
                } label: {
                    Label(localization.language.displayName, systemImage: "globe")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(t("Language", "语言"))
                Spacer()
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Duo Effect").font(.system(size: 27, weight: .semibold, design: .rounded))
                    Text(t("Your screen lingers, blurring as the lid closes.", "画面停留，随合盖渐入虚化。"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(t("Enable", "启用"), isOn: $model.enabled).toggleStyle(.switch).labelsHidden().tint(accent)
                    .accessibilityLabel(t("Enable the blur effect", "启用毛玻璃效果"))
            }
            VStack(spacing: 10) {
                HStack(spacing: 20) {
                    Image(systemName: "laptopcomputer").font(.system(size: 55, weight: .ultraLight)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.angle.map { String(format: "%.0f°", $0) } ?? "—°")
                            .font(.system(size: 47, weight: .light, design: .rounded)).monospacedDigit()
                        Text(t("Current lid angle · closed is 0°", "当前开合角度 · 合盖为 0°"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Divider()
                HStack {
                    Circle().fill(model.radius > 0 ? accent : Color.green).frame(width: 6, height: 6)
                    Text(model.stateText).font(.callout)
                    Spacer()
                }
            }
            .padding(18).background(accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label(t("Clear threshold", "清晰阈值"), systemImage: "angle")
                    Spacer()
                    Text("\(Int(model.threshold))°").monospacedDigit().foregroundStyle(accent)
                }
                Slider(value: $model.threshold, in: 10...140, step: 1).tint(accent)
                    .accessibilityLabel(t("Clear threshold angle", "清晰阈值角度"))
                Text(t("\(Int(model.threshold))° is the clear threshold; closing further folds the screen over the image fixed in space, using your measured eye position.",
                       "角度 ≥ \(Int(model.threshold))° 时清晰；合盖时屏幕以你测得的眼睛位置，在固定的画面之上折叠。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Label(t("Maximum blur", "最大模糊强度"), systemImage: "drop.halffull")
                    Spacer()
                    Text("\(Int(model.maximum))").monospacedDigit().foregroundStyle(accent)
                }
                Slider(value: $model.maximum, in: 1...60, step: 1).tint(accent)
                    .accessibilityLabel(t("Maximum blur strength", "最大模糊强度"))
                HStack {
                    Label(t("Perspective", "透视强度"), systemImage: "perspective")
                    Spacer()
                    Text("\(Int((model.perspective * 100).rounded()))%").monospacedDigit().foregroundStyle(accent)
                }
                Slider(value: $model.perspective, in: 0...1, step: 0.05).tint(accent)
                    .accessibilityLabel(t("Perspective strength", "透视强度"))
                Text(t("Head-coupled off-axis projection: the image stays fixed in space and the screen is a viewport moving over it. 0% keeps the screen flat and only dims and blurs.",
                       "头动耦合的离轴透视：画面固定在空间中，屏幕作为视口在其上移动。0% 屏幕不变形、只暗化和模糊。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Label(t("Viewing position", "观看位置"), systemImage: "person.crop.circle")
                    Spacer()
                    Button(action: { model.assumeCentered?() }) {
                        Text(t("Assume centered", "视为居中"))
                    }
                    .disabled(model.calibrating)
                    Button(action: { model.calibrateEye?() }) {
                        Text(model.calibrating ? t("Measuring…", "测量中…") : t("Calibrate", "校准"))
                    }
                    .disabled(model.calibrating)
                }
                Text(model.eyeStatusText)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Label(t("Auto-calibrate after reopening", "重新打开后自动校准"), systemImage: "arrow.clockwise")
                    Spacer()
                    Toggle("", isOn: $model.autoCalibrate).labelsHidden().toggleStyle(.switch).tint(accent)
                        .accessibilityLabel(t("Auto-calibrate after reopening", "重新打开后自动校准"))
                }
                Text(t("Off by default. When on, ten seconds after you reopen the lid and sit still, the camera measures your position once and turns off again.",
                       "默认关闭。开启后，重新打开屏幕并静坐十秒时会自动测量一次观看位置，随后摄像头关闭。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider().padding(.vertical, 2)
                HStack {
                    Label(t("Detected model", "检测到的机型"), systemImage: "ruler")
                    Spacer()
                    Text(model.detectedModelName).foregroundStyle(.secondary)
                }
                Text(t("Hinge, standoff and camera offsets are preset from Apple's published display and body dimensions.",
                       "转轴、屏幕间距和摄像头偏移按 Apple 公布的屏幕与机身尺寸预设。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup(isExpanded: $showLidAdvanced) {
                    Toggle(t("Override detected values", "覆盖检测值"), isOn: Binding(
                        get: { !model.useDetectedLidGeometry },
                        set: { model.useDetectedLidGeometry = !$0 }))
                        .toggleStyle(.switch).tint(accent)
                        .accessibilityLabel(t("Override detected hinge geometry", "覆盖检测到的转轴尺寸"))
                    Text(model.useDetectedLidGeometry
                         ? t("Manual values replace the detected preset. Measure them against the lid's hinge axis.",
                             "手动数值将替代检测预设。请以转轴为基准测量。")
                         : t("Measuring against the hinge axis: the display's bottom row, the display surface, and the camera in the notch, all in millimetres.",
                             "以转轴为基准测量：显示区底行、显示表面、刘海内摄像头，单位均为毫米。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !model.useDetectedLidGeometry {
                        HStack(spacing: 10) {
                            lidField(t("Hinge drop", "转轴下沿"), value: $model.lidHingeDropMM, accent: accent)
                            lidField(t("Standoff", "屏幕间距"), value: $model.lidStandoffMM, accent: accent)
                        }
                        HStack(spacing: 10) {
                            lidField(t("Camera inset", "摄像头内缩"), value: $model.lidCameraInsetMM, accent: accent)
                            lidField(t("Camera recess", "摄像头凹陷"), value: $model.lidCameraRecessMM, accent: accent)
                        }
                        Button(t("Reset to detected", "恢复检测值")) {
                            model.lidHingeDropMM = LidGeometry.hingeDropMillimetres
                            model.lidStandoffMM = LidGeometry.standoffMillimetres
                            model.lidCameraInsetMM = LidGeometry.cameraInsetMillimetres
                            model.lidCameraRecessMM = LidGeometry.cameraRecessMillimetres
                            model.useDetectedLidGeometry = true
                        }
                        .buttonStyle(.borderless).font(.caption)
                    }
                } label: {
                    Text(t("Advanced override", "高级覆盖")).font(.caption)
                }
            }.padding(.vertical, 2)

            if !model.permission {
                VStack(alignment: .leading, spacing: 8) {
                    Label(t("Screen Recording permission required", "需要屏幕录制权限"),
                          systemImage: "rectangle.dashed.badge.record").font(.callout.weight(.medium))
                    Text(t("Used to blur the built-in display live. Frames stay in memory — nothing is saved or uploaded. The camera runs only when you click Calibrate, to freeze your viewing position; those frames also stay in memory. If the effect does not start after granting, quit and reopen the app.",
                           "用于实时模糊内置屏幕。画面仅在内存中处理，不保存、不上传。仅在你点击“校准”时短暂读取摄像头，以冻结观看位置；画面同样仅在内存中处理。授权后若未生效，请退出并重新打开。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(t("Grant Screen Recording…", "授权屏幕录制…")) { model.requestPermission?() }
                        .buttonStyle(.borderedProminent).tint(accent)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            } else if let error = model.error {
                VStack(alignment: .leading, spacing: 7) {
                    Text(error.text).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    Button(t("Retry", "重试")) { model.retry?() }
                }
            } else {
                Label(model.sensorStatus.text, systemImage: model.angle == nil ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // The 4-second preview is still wired up in AppController; only its
            // button is withheld from the settings window.
            HStack {
                Spacer()
                Button(t("Quit", "退出")) { model.quit?() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Text(t("Built-in display only · pause from the menu bar · normal lid-close sleep preserved",
                   "仅内置屏幕 · 菜单栏随时暂停 · 保留正常合盖睡眠"))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(26).frame(width: 480, height: 900).background(Color(nsColor: .windowBackgroundColor))
    }
}
