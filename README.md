# MOUSE

一个轻量的原生 macOS 菜单栏应用：**触控板保持系统滚动方向，普通及精细鼠标滚轮使用相反方向。**

SwiftUI + AppKit，无第三方依赖，支持 macOS 13 及以上。

## 使用

1. 打开 `dist/MOUSE.app`。建议先把它拖到「应用程序」文件夹，以后从固定位置运行。
2. 点击「打开系统设置」，在系统的辅助功能权限列表中允许 MOUSE。不同 macOS 版本的权限名称可能有所变化，以系统授权提示为准。
3. 返回 MOUSE，状态会变为「正在运行」。如果权限列表没有 MOUSE，可用列表的 `+` 按钮添加正在运行的应用。
4. 关闭窗口后，应用仍在菜单栏运行。点击菜单栏的上下箭头可打开控制面板；右键可快速启停或退出。

系统「自然滚动」开启时，触控板保持自然滚动，普通鼠标改为传统滚动；关闭时，两者的行为相应互换。应用同时反转鼠标的纵向和横向滚动。

「登录时启动」默认关闭，可以在面板中自行开启。暂停或退出 MOUSE 会立即恢复系统原本的滚动行为。

## 构建

安装 Apple Command Line Tools（或 Xcode），使用支持 Swift 5.9 及以上的工具链：

```sh
./scripts/build.sh
open dist/MOUSE.app
```

调试构建：

```sh
./scripts/build.sh --debug
```

构建脚本会生成应用图标，组装 `.app` 并执行本机临时签名。输出架构为当前工具链的默认架构；它不是经过 Developer ID 签名和 Apple 公证的发行版。重新构建或移动应用后，系统可能要求重新授权。

也可以使用 Xcode 打开 `Package.swift` 编辑源码。实际使用时请运行打包后的 `.app`，确保权限归属到 MOUSE。

## 验证

自动测试使用 Swift Testing，需要 Swift 6 / Xcode 16 或更新的工具链。测试覆盖普通及精细滚轮的方向转换、事件元数据保留，以及触控板手势和惯性事件完整保留，不发送全局输入事件，不需要辅助功能权限。

```sh
swift test --disable-sandbox --scratch-path .build \
  --cache-path .build/cache --config-path .build/config --security-path .build/security
```

实机检查：

- 授权并启用后，在同一可滚动窗口分别使用触控板和鼠标滚轮，确认方向相反。
- 检查触控板惯性滚动仍然正常；如果鼠标支持横向滚轮，再检查横向滚动。
- 关闭开关、重新开启和退出应用，确认功能及时生效或恢复。
- 取消权限后应显示「等待授权」，重新授权后应恢复运行。
- 从睡眠唤醒后检查滚动；开启登录项后，在下次登录时确认菜单栏图标出现。

## 兼容范围

支持普通 USB / 蓝牙鼠标，以及 MX Master 3 等报告精细像素滚动的滚轮。macOS 的公开 Quartz 滚动事件不提供一个可靠的「鼠标 / 触控板」设备类型字段，因此 MOUSE 根据手势阶段和惯性阶段区分来源：两个阶段均为零的滚轮事件反转；带有任意手势或惯性阶段的事件保持原样，包括触控板惯性的开始、持续和结束。

「连续滚动」标记表示像素精度，不能直接用来判断设备类型。实测 MX Master 3 即使关闭 Logi Options+ 的平滑滚动，仍会报告连续、无手势阶段的滚轮事件；MOUSE 1.0.1 已支持这类输入。

**Magic Mouse 和模拟触控手势的鼠标驱动可能使用与触控板相同的阶段标记，因此不保证能被反转。** 如果第三方驱动将触控板转换为无阶段的滚轮事件，公开事件字段也无法可靠区分来源。不要同时开启多个修改滚动方向的工具，否则可能重复反转。

MOUSE 只处理滚轮事件，不记录键盘输入，不联网，也不修改系统的「自然滚动」偏好。

## 源码

```text
Sources/MOUSE/           界面、菜单栏、权限及登录项
Sources/ScrollCore/      滚动事件识别、反转及事件监听生命周期
Tests/ScrollCoreTests/   核心回归测试
Resources/Info.plist     应用信息
scripts/                构建与图标生成
dist/MOUSE.app           构建产物
```

事件处理使用 Apple 的 [CGEvent event tap](https://developer.apple.com/documentation/coregraphics/cgevent)，登录项使用 [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)。事件监听会在暂停和退出时释放，并在超时和系统唤醒后尝试恢复。
