# macOS 本地接续说明

最新全量处理结果见 [ISSUE_RESOLUTION.md](ISSUE_RESOLUTION.md)。已追加 iPhone 16 Pro 真机验收与 example Scene 启动修复，见 MACOS_VALIDATION.md 末尾。下面保留第一轮交接与验证背景，其中待办状态不是最新状态。

## 当前目标与状态

继续处理 #3（SwiftSocket 的 Swift 版本导致 iOS 构建失败）和 #8（SPM / Capacitor 8）。
用户要求：**必须把插件实际接入 example，运行原生应用并验证真实 TCP 收发。**
截至云端交接时是待验证实现。**2026-11-01 已完成本机 iOS 模拟器接续验证：
CocoaPods / SPM example 均编译成功、各自实际运行并通过真实 TCP smoke test；
CocoaPods 与 SPM 原生测试各 3 项通过、0 失败。**
环境、执行命令、日志证据和验证边界见 [MACOS_VALIDATION.md](MACOS_VALIDATION.md)。
这不改变下表中的历史云端结果，也不代表 Android 云端失败或 iOS 真机问题已解决。

已实现：

- 用 Apple Network.framework 替换 SwiftSocket；连接、读取、超时和关闭使用异步队列。
- 用 CAPBridgedPlugin 注册 iOS 插件，增加 Package.swift，保留 CocoaPods。
- npm 包包含 Swift package 引用的源码和测试目录。
- 开发依赖及本地 example 统一到 Capacitor 8；更新 Android / iOS 开发工程。
- example 通过 `file:../` 使用本地插件，增加 `Run TCP smoke test` 按钮和回显服务器。
- 增加 Android example 原生测试、浏览器测试、3 项 Swift socket 测试及 CI。

云端实际验证：

| 检查 | 结果 |
| --- | --- |
| 插件 TypeScript / Rollup、example Vite 构建 | 通过 |
| ESLint、补丁格式检查 | 通过 |
| Chromium example 测试 | 2 项通过；只验证浏览器拒绝 TCP |
| npm pack 产物接入临时 SPM example、生成并同步 | 通过；未编译 iOS |
| Android 独立插件、example APK / 测试 APK 构建 | 通过 |
| Android example 原生测试 | 实际执行 2 项，1 项通过；TCP 用例在 `WebView callback timed out` 处失败，未进入 TCP 断言 |
| iOS 编译、模拟器、Swift socket 测试 | 未执行，云环境为 Linux |

云端没有 KVM。已尝试两种 Android 镜像、系统 Watchdog 超时配置及软件图形后端；
原生 WebView 的基础 JS / 空白页诊断也未正常响应。**尚未确认这是环境性能、图形兼容性还是其他启动问题，不能据此归因于 TCP 插件。**
启动屏自动隐藏的对照实验未解决问题，已还原。不要重复云端长时间的软件模拟器排查；优先在本机验证 iOS。

## 本机准备与构建

需要 Node 22+、完整 Xcode（Capacitor 8 要求 Xcode 26+）、已安装的 iOS Simulator runtime，
以及 CocoaPods。先检查实际工具版本和 `xcode-select -p` 是否指向完整 Xcode。
不要使用云端 `/workspace/toolchains`、代理配置或 JDK 路径；那些只适用于 Linux 云机。

从仓库根目录运行：

```sh
npm ci
npm run build
cd example
npm ci
npm run build
npx cap sync ios
npx cap run ios --list
```

根据实际列表选择可用的 iPhone 模拟器 UDID，然后运行：

```sh
npx cap run ios --target <UDID>
```

若需要手动检查 Xcode 工程，打开 `example/ios/App/App.xcworkspace`，使用 `App` scheme。
先解决真实编译和启动错误，保留错误信息；不能以 `cap sync` 成功代替原生构建成功。

## 必须执行的真实 example TCP 验证

在另一个终端，从 `example/` 启动服务器：

```sh
npm run test:server
```

在实际运行的 iOS example 中，填写 `127.0.0.1`、端口 `9100`，点击
**Run TCP smoke test**。iOS 模拟器可通过该地址连接 Mac 主机。
这条链路使用真实插件和 TCP server，不使用 WebSocket 替代或 socket mock。

必须看到成功结果，并确认以下场景：

1. 两次连续 UTF-8 收发。
2. Hex 和 Base64 二进制往返。
3. 一次响应分多次短读，剩余数据不丢失。
4. 无数据读取超时后，仍能读取随后发送并延迟回显的数据。
5. 对端关闭后，读取以 `EOF` 拒绝；最后清理连接。

如果本地工具没有 GUI 自动化能力，请明确告诉用户需要在 Simulator 中点击按钮并收集日志，
不能自行把未执行的交互描述为通过。真机使用 Mac 的局域网 IP，不能使用手机自己的 `127.0.0.1`。

## SPM 与 Swift 原生测试

在 `example/` 运行：

```sh
npm run test:spm
```

该脚本从实际 `npm pack` 产物生成临时 SPM example，执行 `cap add/sync ios`，
并且在 macOS 上执行 simulator 构建。注意检查真实的 Xcode 输出和退出状态。

再回到仓库根目录，检查可用 scheme / simulator 并运行原生测试，例如：

```sh
xcodebuild -list
xcrun simctl list devices available
xcodebuild -scheme CapacitorTcpSocket \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  CODE_SIGNING_ALLOWED=NO test
```

scheme 名称和设备以本机实际输出为准。测试位于 `ios/PluginTests/TcpSocketTests.swift`，
覆盖连续短读和剩余缓存、超时后数据保留和本地主动关闭、对端 EOF。
除了 SPM 构建与测试，也要保留上面 CocoaPods example 的实际运行验证。

## 其他 issue 和范围

- #1：历史 Android 实现曾每次新建 BufferedInputStream，可能丢失预读数据；当前实现已改为原始 InputStream。新增短读回归，但原报告尚未确认解决。
- #2：原先已关闭的 Capacitor 7 支持请求。
- #4：用户明确表示目前没有 iOS 真机复现信息，保持待复现。example 已添加局域网用途说明；不能声称真机问题已修复。
- #5：TCP 服务端 bind/listen/accept 尚未实现，是后续独立功能。

先完成 #3/#8 的本机编译、SPM / CocoaPods 接入和真实 example TCP 验证，再评估后续工作。
不要发布 npm、创建版本标签、关闭 issue 或合并主分支，除非用户另行要求。
