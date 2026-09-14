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

保留梯形透视：底边和高度固定，合盖时顶边按原收窄曲线逐渐向内收，不再纵向先缩小再放大。透视强度可调；同时按合盖进度逐渐淡至黑色、增加虚化。模糊半径即时跟随 60 Hz 传感器目标值，透视与变暗使用 15ms 的短时滤波来隐藏传感器的整数角度跳变；屏幕捕获在阈值上方 12° 内预热，首个效果帧无需等待重新启动 ScreenCaptureKit，达到阈值时覆盖层仍立即隐藏。模糊半径还沿高度渐变：转轴端约为最大半径的 5%，摄像头端为最大半径；使用 CIMaskedVariableBlur 连续变化。保留 60 帧 Metal 渲染。

- `./scripts/render-check.sh` 生成 `docs/effect-preview.png`，用合成画面验证图像处理链，不读取屏幕内容。
- `./scripts/settings-render.sh` 离屏渲染设置窗口的英文和中文版本到 `.build/settings-en.png` 和 `.build/settings-zh.png`，作为文案和排版检查；不涉及屏幕捕获和权限。控件没有强调色，因为只有活动应用的 key 窗口才会画出强调色，所以 `docs/settings-*.png` 是应用的真实截图。
- `./scripts/make-icon.sh` 从 `Resources/AppIcon.png` 重新生成 `Resources/AppIcon.icns`；换图标时替换那张 1024×1024 图再跑它。

## 流畅度检查

`./scripts/benchmark.sh` 对 3024×1964 合成画面比较旧位图输出与 Metal 输出。初次本机测量中位数分别约 12.9ms / 4.7ms（不代表端到端帧率）。`./scripts/metal-check.sh` 验证实际纹理上下方向。核心测试同时覆盖模糊即时跟随、几何参数按时间插值和达到阈值立即清晰。

## 调试模式

Duo Effect 是菜单栏应用，没有控制台，突然退出时除了系统崩溃报告什么都留不下。在菜单栏菜单里选「开启调试日志」，或用 `--debug` 启动，生命周期事件会写入 `~/Library/Logs/Duo Effect/debug.log`（也可在「控制台」中按 `local.ruixiang.macbookduo` 子系统查看）。「显示调试日志…」会在访达中定位该文件。

日志记录捕获的启停、渲染器的创建与释放、效果开关及当时的角度和阈值、传感器与权限变化、睡眠唤醒挂起，以及错误。逐帧输出被刻意省略，只记录异常帧。文件超过 4 MB 自动轮转。

## 技术参考

- [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor)：传感器 HID usage 与 feature-report 协议信息。
- [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)：排除应用自身的本地屏幕捕获。
