# Issue 处理与兼容性验收（2026-11-01）

本记录覆盖 `14851d4` 之后的兼容性修正与服务端功能。第一轮云端和 macOS 验证保留在 MACOS_HANDOFF.md、MACOS_VALIDATION.md；本轮通过不能改写历史失败。

## 逐项处理

仓库 #1–#8 包含 6 个 issue 和 2 个 PR。

| 编号 | 技术处理结果 |
| --- | --- |
| #1 | Android/iOS 实际 example 连续两次收发、连续短读、超时后数据均通过。历史 Android 缓冲输入流修正来自已合并 #7；本轮补齐回归，并修正 iOS 读取队列和超时后的数据保留。原报告缺少平台/版本/复现代码，不能声称识别了其唯一根因。 |
| #2 | 历史已关闭；本轮额外用实际 npm 包接入 Capacitor 7.6.10，iOS 编译和完整 TCP smoke test 通过。 |
| #3 | 移除 SwiftSocket，使用 Network.framework；CocoaPods/SPM 构建和实际运行通过。 |
| #4 | 已在 GitHub 更新调查结果并向报告者索取真机版本、错误、权限及服务端连接记录；保留 open。没有真机证据，不能宣称已解决。 |
| #5 | 新增 iOS/Android `listen`、`accept`、`closeServer`。监听默认 loopback，显式设置 0.0.0.0 才接收 LAN 连接；已接受的连接复用原有客户端 API。两平台实际 smoke test 验证超时、双向二进制、关闭监听拒绝等待、已连接客户端继续可用。 |
| #6 | 历史关闭、未合并的内部包仓库 PR，不是待修复缺陷。 |
| #7 | 历史已合并的 Android timeout/EOF PR；本轮真实 Android 测试覆盖相关行为。 |
| #8 | Capacitor 8、SPM npm 包接入、CocoaPods 接入均通过；本机 Android 原生测试通过。 |

#4 是唯一尚缺复现证据的真实问题。不能将“全部已处理”表述为“全部问题已证实修复”。GitHub 的最终状态及提交号以本次操作结果为准。

## 原有能力和行为兼容

- 原 `connect/send/read/disconnect` 接口、默认端口、编码和客户端编号用法保留。
- iOS EOF 默认返回空串，保持旧版行为；新增 `rejectOnEOF: true` 可显式获得 EOF 错误码。Android 默认继续拒绝 EOF，也支持显式 false。
- iOS 重复 disconnect 已成功连接过的 client 仍成功；不存在的 client 仍拒绝。
- iOS 空串发送和旧版奇数位 Hex 解析行为保留；无效端口、非正读取长度、负超时明确拒绝。
- 同一 iOS client 的并发 read 按调用顺序排队；超时不会丢掉仍在接收中的数据。
- 对端半关闭发送方向后，本端仍可以 send；已通过真实 NWConnection 测试。
- Android 默认最低 API 恢复 23，优先采用宿主配置；服务端集合实现不使用 API 24 专属工厂方法。
- 服务端功能为增量接口；关闭监听不关闭已接受的客户端。每个 server 同时允许一个待处理 accept。手机后台运行仍服从宿主和操作系统限制。

## 真实验证

- iOS：Xcode 27、iPhone 17 Pro / iOS 26.5。CocoaPods 和 SPM 构建成功；两套 XCTest 各 5 项通过（同一组测试，不是 10 个不同场景）。
- 实际 GUI 点击 example 的 smoke test：Capacitor 8 CocoaPods、Capacitor 8 SPM、Capacitor 7 CocoaPods，均检查页面成功结果与原生桥接日志。
- Android：本机硬件加速 Medium_Phone / Android 17（API 37）、Temurin JDK 21、Gradle 8.14.3；`connectedDebugAndroidTest` 两项通过，其中一项执行真实 Activity → WebView JS → 原生 TCP 客户端及服务端完整流程。
- 浏览器：Playwright 两项通过，验证浏览器明确拒绝直接 TCP。
- TypeScript/Rollup、Vite、ESLint、git diff 格式检查通过。

连续收发、UTF-8、Hex/Base64、短读余量、超时后延迟数据、默认/显式 EOF、重复断开、服务端 accept 超时、双向收发、关闭监听均在实际应用流程中检查。并发读取与半关闭发送另由 Swift 原生测试验证。

## 环境失败和边界

- Android 首次使用 Android Studio 内置 Java 25，Gradle 报 `Unsupported class file major version 69`。改用临时目录的官方 Temurin JDK 21 后构建与测试成功。
- Capacitor 7 工程默认 iOS 14；Xcode 27 拒绝低于 iOS 15 的部署目标。只给测试构建传入 `IPHONEOS_DEPLOYMENT_TARGET=15.0` 后成功；没有因此修改插件 CocoaPods 的 iOS 14 声明。本轮未验证真实 iOS 14 设备。
- 浏览器测试最初缺少对应 Chromium，安装 Playwright 官方 headless shell 后通过。沙箱监听限制通过工具权限解决。
- 云端 Android WebView 超时仍是历史失败；本机通过不能证明云端失败的确切原因。
- 未进行 iOS 真机验收、应用商店归档或 npm 发布；没有“所有设备绝对无 bug”的证据。

## 证据

精简日志保存于 `validation/2026-11-01/` 的 `final-*` 文件。完整临时日志位于 `/private/tmp/tcp-*.log`，可能被系统清理。测试代码位于 `ios/PluginTests/TcpSocketTests.swift`、`example/src/js/smoke-test.js` 与 Android `TcpExampleTest.java`，可持续重跑。
