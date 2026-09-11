# 开发说明

*[English](DEVELOPMENT.md)* · 返回 [README](../README.zh-CN.md)。

## 构建和检查

需要 Xcode 或兼容的 Apple Swift 编译工具，以及钥匙串中可用的 Apple Development / Developer ID 签名身份，不依赖第三方软件包。仅有一个身份时自动选择；多个身份时用 `CODE_SIGN_IDENTITY` 指定证书 SHA-1。构建前退出正在运行的应用。

```sh
./scripts/test.sh
./scripts/build.sh
"dist/Duo Effect.app/Contents/MacOS/DuoEffect" --probe
"dist/Duo Effect.app/Contents/MacOS/DuoEffect" --self-check
```

构建脚本故意拒绝临时签名：那会让每次重新构建后已存储的屏幕录制授权失效。稳定证书签名可避免这一点。当前使用本机 Apple Development 证书签名，未做 Developer ID 公证。

直接从终端运行 `--self-check` 的权限结果属于启动它的终端上下文，不能作为图形应用已获授权的证据；请以应用窗口中的授权状态为准。

## 人工验收

授权屏幕录制后，检查：低于阈值时逐渐模糊，重新打开至阈值时完全清晰；移动窗口和播放普通视频时背景持续更新；暂停和退出恢复原画面；外接显示器保持正常；锁屏、睡眠和唤醒后无残留效果。

## 效果模型

低于清晰阈值时，把屏幕视为固定在阈值角度上，而盖子在真实移动，观察者正对这块参考屏幕看：视线垂直于参考平面，不随盖子转动。视线是平行的，所以画面不会横向移动。沿这条视线看，倾斜了 x − y 的盖子只有 cos(x − y) 倍的高度，因此内容从共用的铰链起沿盖子拉伸 1 / cos(x − y)，超出盖子顶边的部分不显示——相差 60° 时只剩下半幅画面。只有两个平面之间的夹角起作用，拉伸封顶 3 倍。「透视强度」滑块控制这套几何应用多少，0% 画面不变形，100% 完整投影。最大暗化为 65%，高斯模糊强度可调。Retina 原始分辨率捕获，60 帧/秒，Core Image 直接写入 Metal 显示纹理；透视、暗化与模糊按时间统一平滑，仅在效果生效时运行捕获。设置窗口保持可读；效果层不拦截鼠标。

- `./scripts/render-check.sh` 生成 `docs/effect-preview.png`，用合成画面验证图像处理链，不读取屏幕内容。
- `./scripts/settings-render.sh` 离屏渲染设置窗口的英文和中文版本到 `docs/settings-en.png` 和 `docs/settings-zh.png`，验证文案和排版。ImageRenderer 无法栅格化 AppKit 控件，语言菜单、开关和滑块在输出里是占位色块。
- `./scripts/make-icon.sh` 从 `Resources/AppIcon.png` 重新生成 `Resources/AppIcon.icns`；换图标时替换那张 1024×1024 图再跑它。

## 流畅度检查

`./scripts/benchmark.sh` 对 3024×1964 合成画面比较旧位图输出与 Metal 输出。初次本机测量中位数分别约 12.9ms / 4.7ms（不代表端到端帧率）。`./scripts/metal-check.sh` 验证实际纹理上下方向。核心测试同时覆盖按时间插值和达到阈值立即清晰。

## 调试模式

Duo Effect 是菜单栏应用，没有控制台，突然退出时除了系统崩溃报告什么都留不下。在菜单栏菜单里选「开启调试日志」，或用 `--debug` 启动，生命周期事件会写入 `~/Library/Logs/Duo Effect/debug.log`（也可在「控制台」中按 `local.ruixiang.macbookduo` 子系统查看）。「显示调试日志…」会在访达中定位该文件。

日志记录捕获的启停、渲染器的创建与释放、效果开关及当时的角度和阈值、传感器与权限变化、睡眠唤醒挂起，以及错误。逐帧输出被刻意省略，只记录异常帧。文件超过 4 MB 自动轮转。

## 技术参考

- [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor)：传感器 HID usage 与 feature-report 协议信息。
- [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)：排除应用自身的本地屏幕捕获。
