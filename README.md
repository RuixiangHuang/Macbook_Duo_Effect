# Duo Effect

原生 macOS 菜单栏应用，按 MacBook 的真实开合角度，让内置屏幕中的画面产生透视、暗化和虚化。

## 运行

打开 `dist/Duo Effect.app`。应用启动后显示设置窗口，菜单栏显示实时角度。

0. 界面默认英语。左上角的地球按钮可切换 English / 简体中文，选择自动保存。
1. 点击「授权屏幕录制…」，在系统设置中允许 **Duo Effect**。
2. 如果 macOS 要求重新打开，退出应用后再次打开。
3. 调整「清晰阈值」，默认 90°。合盖为 0°；达到或超过阈值时移除效果。
4. 以 x 为虚拟画面参考平面，低于阈值时，以底部铰链为基准产生透视收窄和拉伸，同时逐渐变暗、虚化。菜单栏可随时暂停或退出。
5. 「预览 4 秒」临时模拟较小角度，结束后恢复真实传感器控制。

仅内置屏幕生效，顶部菜单栏也参与透视、暗化和虚化。设置窗口保持可读；效果层不拦截鼠标，打开至阈值后恢复正常操作画面。系统合盖睡眠保持正常。设置自动保存。传感器无法读取、屏幕捕获失败或会话进入睡眠/非活动状态时移除效果。

## 权限与兼容性

- macOS 14 或更新，Apple Silicon MacBook，且具有可读开合角度传感器。
- 本机 M1 Pro MacBook Pro 已成功读取 112°；实际运行也会显示传感器状态。
- 屏幕录制权限用于本机实时模糊；不录音，不写屏幕视频到磁盘，不联网。
- 角度传感器的 HID 协议未经 Apple 公开保证，未来系统升级可能影响兼容性。
- 使用本机 Apple Development 证书签名，未做 Developer ID 公证；当前构建面向本机使用。稳定证书签名可避免每次重编译使已有隐私授权失效。
- 受保护的视频内容可能无法被系统捕获。此应用是视觉效果工具，不是隐私屏幕或安全屏障。

## 构建和检查

需要 Xcode 或兼容的 Apple Swift 编译工具，以及钥匙串中可用的 Apple Development / Developer ID 签名身份，不依赖第三方软件包。仅有一个身份时自动选择；多个身份时用 CODE_SIGN_IDENTITY 指定证书 SHA-1。构建前退出正在运行的应用。

```sh
./scripts/test.sh
./scripts/build.sh
"dist/Duo Effect.app/Contents/MacOS/DuoEffect" --probe
"dist/Duo Effect.app/Contents/MacOS/DuoEffect" --self-check
```

## 人工验收

授权屏幕录制后，检查：低于 x 时逐渐模糊，重新打开至 x 时完全清晰；移动窗口和播放普通视频时背景持续更新；预览自动结束；暂停和退出恢复原画面；外接显示器保持正常；锁屏、睡眠和唤醒后无残留效果。

## 效果模型

虚拟观察点固定在参考平面前方约 2.5 个屏幕高度处；不是眼动追踪。极端合盖姿态的投影差角限制在 75°，避免几何翻转。最大暗化为 65%，高斯模糊强度可调。Retina 原始分辨率捕获，60 帧/秒，Core Image 直接写入 Metal 显示纹理；透视、暗化与模糊按时间统一平滑，仅在效果生效时运行捕获。

`./scripts/render-check.sh` 生成 `docs/effect-preview.png`，用合成画面验证图像处理链，不读取屏幕内容。

`./scripts/settings-render.sh` 离屏渲染设置窗口的英文和中文版本到 `docs/settings-en.png` 和 `docs/settings-zh.png`，验证文案和排版。ImageRenderer 无法栅格化 AppKit 控件，语言菜单、开关和滑块在输出里是占位色块。

`./scripts/make-icon.sh` 从 `Resources/AppIcon.png` 重新生成 `Resources/AppIcon.icns`；换图标时替换那张 1024×1024 图再跑它。

## 技术参考

- [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor)：传感器 HID usage 与 feature-report 协议信息。
- [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)：排除应用自身的本地屏幕捕获。

代码按上述接口信息独立实现；没有引入外部代码或软件包。

## 授权一直不生效

早期临时签名构建可能留下与新版不匹配的授权记录。修复版使用证书签名；从早期版迁移需要退出应用，仅重置本应用旧记录，再重新打开并在系统设置中授权一次：

```sh
tccutil reset ScreenCapture local.ruixiang.macbookduo
```

请检查应用窗口中的授权状态。直接从终端运行 --self-check 的权限结果可能属于启动它的终端上下文，不能作为图形应用已获授权的证据。

## 流畅度检查

`./scripts/benchmark.sh` 对 3024×1964 合成画面比较旧位图输出与 Metal 输出。初次本机测量中位数分别约 12.9ms / 4.7ms（不代表端到端帧率）。`./scripts/metal-check.sh` 验证实际纹理上下方向。核心测试同时覆盖按时间插值和达到阈值立即清晰。
