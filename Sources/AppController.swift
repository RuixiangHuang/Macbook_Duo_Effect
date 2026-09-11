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
    var onChange: (() -> Void)?
    var requestPermission: (() -> Void)?
    var preview: (() -> Void)?
    var retry: (() -> Void)?
    var quit: (() -> Void)?
    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["enabled": true, "threshold": 90.0, "maximum": 32.0])
        enabled = defaults.bool(forKey: "enabled")
        let x = defaults.double(forKey: "threshold")
        threshold = x.isFinite ? min(140, max(10, x)) : 90
        let blur = defaults.double(forKey: "maximum")
        maximum = blur.isFinite ? min(60, max(1, blur)) : 32
    }
    var stateText: String {
        if !enabled { return t("Effect paused", "效果已暂停") }
        if !permission { return t("Waiting for Screen Recording permission", "等待屏幕录制授权") }
        if error != nil { return t("Effect paused · retry needed", "效果已暂停 · 需要重试") }
        if angle == nil { return t("Waiting for the lid angle sensor", "等待角度传感器") }
        if previewing { return t("Previewing · restores in 4s", "正在预览 · 4 秒后自动恢复") }
        return radius > 0 ? t("Perspective · dimming · blur active", "透视 · 暗化 · 毛玻璃生效中")
                          : t("Screen is clear", "屏幕清晰")
    }
}

final class AppController: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let sensor = LidSensor()
    private let sensorQueue = DispatchQueue(label: "local.macbookduo.sensor", qos: .userInitiated)
    private var sensorTimer: DispatchSourceTimer?
    private var permissionTimer: Timer?
    private let overlay = BlurOverlay()
    private var statusItem: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var settingsItem: NSMenuItem!
    private var quitItem: NSMenuItem!
    private var angleItem: NSMenuItem!
    private var settings: NSWindow?
    private var suspensionReasons = Set<String>()
    private var sleeping: Bool { !suspensionReasons.isEmpty }
    private var previewDeadline: Date?
    private var observers: [NSObjectProtocol] = []
    private var shuttingDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        model.permission = CGPreflightScreenCaptureAccess()
        model.onChange = { [weak self] in self?.apply() }
        model.requestPermission = { [weak self] in self?.authorize() }
        model.preview = { [weak self] in self?.preview() }
        model.retry = { [weak self] in
            self?.model.error = nil
            self?.model.permission = CGPreflightScreenCaptureAccess()
            self?.apply()
        }
        model.quit = { NSApp.terminate(nil) }
        Localization.shared.onChange = { [weak self] in self?.refreshMenuTitles() }
        overlay.onError = { [weak self] message in
            self?.model.error = message
            self?.model.radius = 0
        }
        let timer = DispatchSource.makeTimerSource(queue: sensorQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let angle = self.sensor.read()
            let status = self.sensor.status
            DispatchQueue.main.async {
                guard !self.shuttingDown else { return }
                self.model.angle = angle
                self.model.sensorStatus = status
                self.apply()
            }
        }
        sensorTimer = timer
        timer.resume()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let permission = CGPreflightScreenCaptureAccess()
            if self.model.permission != permission { self.model.permission = permission; self.apply() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, "system"), (NSWorkspace.screensDidSleepNotification, "display"), (NSWorkspace.sessionDidResignActiveNotification, "session")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.suspensionReasons.insert(reason)
                self?.cancelPreview()
                self?.overlay.clear()
                self?.model.radius = 0
            })
        }
        for (name, reason) in [(NSWorkspace.didWakeNotification, "system"), (NSWorkspace.screensDidWakeNotification, "display"), (NSWorkspace.sessionDidBecomeActiveNotification, "session")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
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
    }
    @objc private func toggle() { model.enabled.toggle() }
    @objc private func terminate() { NSApp.terminate(nil) }

    private func apply() {
        guard !shuttingDown else { return }
        if let deadline = previewDeadline, Date() >= deadline { cancelPreview() }
        if !model.enabled { cancelPreview() }
        let angle = model.previewing ? model.threshold * 0.25 : model.angle
        let desired = EffectModel.radius(angle: angle, threshold: model.threshold, maximum: model.maximum,
                                         enabled: model.enabled && model.permission && !sleeping && model.error == nil)
        // The renderer interpolates all visual properties on its 60 Hz frame clock.
        model.radius = desired
        overlay.update(radius: model.radius, geometry: EffectModel.geometry(angle: angle, threshold: model.threshold))
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Duo Effect"
            window.titlebarAppearsTransparent = true
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

struct SettingsView: View {
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
                Text(t("\(Int(model.threshold))° is the reference plane; closing further adds perspective, dimming and blur.",
                       "以 \(Int(model.threshold))° 为画面参考平面；向下合盖时透视变形、变暗和虚化。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Label(t("Maximum blur", "最大模糊强度"), systemImage: "drop.halffull")
                    Spacer()
                    Text("\(Int(model.maximum))").monospacedDigit().foregroundStyle(accent)
                }
                Slider(value: $model.maximum, in: 1...60, step: 1).tint(accent)
                    .accessibilityLabel(t("Maximum blur strength", "最大模糊强度"))
            }.padding(.vertical, 2)

            if !model.permission {
                VStack(alignment: .leading, spacing: 8) {
                    Label(t("Screen Recording permission required", "需要屏幕录制权限"),
                          systemImage: "rectangle.dashed.badge.record").font(.callout.weight(.medium))
                    Text(t("Used to blur the built-in display live. Frames stay in memory — nothing is saved or uploaded. If the effect does not start after granting, quit and reopen the app.",
                           "用于实时模糊内置屏幕。画面仅在内存中处理，不保存、不上传。授权后若未生效，请退出并重新打开。"))
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
        .padding(26).frame(width: 480, height: 660).background(Color(nsColor: .windowBackgroundColor))
    }
}
