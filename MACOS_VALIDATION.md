# macOS iOS 原生验证记录

本文件记录第一轮、提交 `14851d4` 的验证快照。后续兼容性修正、服务端能力和 Android 本机验收见 [ISSUE_RESOLUTION.md](ISSUE_RESOLUTION.md)。

## 结论与范围

2026-11-01（Asia/Shanghai），基于提交 `14851d486ba82b22faecd401944d48753aeed5c3`，
本机完成 CocoaPods / SPM 编译、两条集成路径的 Swift 原生测试，以及两种 example 的实际 TCP 收发。
本次未修改插件实现、测试断言、依赖锁文件或 CI；只补充验证记录及日志摘录。

| 检查 | 实际结果 |
| --- | --- |
| 插件 TypeScript / Rollup、example Vite 构建 | 通过 |
| CocoaPods example `App` 模拟器构建 | 退出 0，`BUILD SUCCEEDED` |
| npm pack 产物接入临时 SPM example 并构建 | 退出 0，`BUILD SUCCEEDED`；不只是 add / sync |
| SPM `CapacitorTcpSocket` 原生测试 | 退出 0，3 项通过、0 失败，`TEST SUCCEEDED` |
| CocoaPods `PluginTests` 原生测试 | 退出 0，3 项通过、0 失败，`TEST SUCCEEDED` |
| CocoaPods example 安装、启动、GUI 点击 smoke test | 通过；页面显示 `Smoke test passed`，原生桥接记录完整收发 |
| npm pack 产物生成的 SPM example 安装、启动、GUI 点击 smoke test | 通过；页面显示 `Smoke test passed`，原生桥接记录完整收发 |

**此前云端原生验证尚未通过：Android 原生测试执行 2 项、1 项通过，TCP 用例在
`WebView callback timed out` 失败，未进入 TCP 断言；iOS 在 Linux 云端未执行。**
这些历史结果仍然有效，本次未重新验证 Android，不能将云端失败归因于或宣称已修复 TCP 插件。
本次结果仅支持当前代码在下述本机 iOS 模拟器环境的编译与运行；未验证 iOS 真机、签名归档、
最低 iOS 版本、Capacitor 7 或全部 Xcode 版本，不能据此关闭真机待复现的 #4。
未提交、推送、合并、发布 npm、创建标签或关闭 issue。

## 实际环境

- Apple Silicon arm64；macOS 27.0.1（26A434）。
- Xcode 27.0（27A266a）；`xcode-select -p` 为 `/Applications/Xcode.app/Contents/Developer`。
- Apple Swift 6.4（swiftlang-6.4.0.34.1）；CocoaPods 1.17.0。
- Node 24.18.0；npm 11.16.0；插件包版本 7.1.1。
- CocoaPods / SPM 实际使用 Capacitor 8.6.0；Camera 8.2.6，SplashScreen 8.0.2。
- iPhone 17 Pro，iOS 26.5（23F77）；UDID `872FF11E-CC22-4D95-9A73-51BF24EC78D6`。
- GUI 使用 Xcode 27 的 `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`。
  此 Xcode 安装没有旧路径下的 `Simulator.app`。

默认工具沙箱访问 CoreSimulator 时出现 connection invalid / operation not permitted；
授予命令访问本机服务后，设备查询、启动、安装和测试均成功。
一次从仓库根目录执行的 `npm --prefix example exec -- cap sync ios` 误读默认 `./www` 后失败；
改为在 `example/` 目录执行 `npx cap sync ios` 后成功。该失败发生在同步阶段，不是原生编译失败。

## 执行方式

下面命令从仓库根目录执行；省略了实际使用的日志重定向。两处 `npm ci` 均使用锁文件，
缓存位于 `/private/tmp/tcp-socket-npm-cache`。

```sh
npm ci --cache /private/tmp/tcp-socket-npm-cache
(cd example && npm ci --cache /private/tmp/tcp-socket-npm-cache)
npm run build
npm --prefix example run build
(cd example && npx cap sync ios)

xcrun simctl boot 872FF11E-CC22-4D95-9A73-51BF24EC78D6
xcrun simctl bootstatus 872FF11E-CC22-4D95-9A73-51BF24EC78D6 -b

xcodebuild -workspace example/ios/App/App.xcworkspace -scheme App \
  -destination 'platform=iOS Simulator,id=872FF11E-CC22-4D95-9A73-51BF24EC78D6' \
  -derivedDataPath /private/tmp/tcp-socket-validation-20261101/pods-derived \
  CODE_SIGNING_ALLOWED=NO build

(cd example && npm run test:spm)

xcodebuild -scheme CapacitorTcpSocket \
  -destination 'platform=iOS Simulator,id=872FF11E-CC22-4D95-9A73-51BF24EC78D6' \
  -derivedDataPath /private/tmp/tcp-socket-validation-20261101/spm-test-derived \
  -resultBundlePath /private/tmp/tcp-socket-validation-20261101/spm-tests.xcresult \
  CODE_SIGNING_ALLOWED=NO test

(cd ios && pod install && xcodebuild -workspace Plugin.xcworkspace -scheme PluginTests \
  -destination 'platform=iOS Simulator,id=872FF11E-CC22-4D95-9A73-51BF24EC78D6' \
  -derivedDataPath /private/tmp/tcp-socket-validation-20261101/plugin-pods-derived \
  -resultBundlePath /private/tmp/tcp-socket-validation-20261101/pods-tests.xcresult \
  CODE_SIGNING_ALLOWED=NO test)
```

SPM fixture 为 `/private/var/folders/9p/33kz0pws71j_jq32sfgqvngm0000gn/T/tcp-spm-example-Oy4MMv`。
脚本从实际 `npm pack` 压缩包提取插件，执行 Capacitor add / sync 和 simulator build；
其 App 产物位于 `/Users/svend/Library/Developer/Xcode/DerivedData/App-efdcynnwolqqpacbybzkkgrubpro/Build/Products/Debug-iphonesimulator/App.app`。

两套原生测试均执行以下同一组测试，不是 6 个不同用例：

1. `testRepeatedReadsAndBufferedRemainder`：连续发送和短读、保留剩余缓存。
2. `testTimeoutDoesNotLoseNextReceiveAndCloseRejectsPendingRead`：超时后数据保留，主动关闭拒绝挂起读取。
3. `testPeerCloseReportsEOF`：对端关闭触发 EOF。

SPM 测试在 19:45:31 完成，耗时 1.680 秒；CocoaPods 测试在 19:46:30 完成，耗时 1.678 秒。

## 实际 example 与真实 TCP

运行 `example/scripts/echo-server.mjs`，监听本机 9100 端口；两套 App 均通过
`xcrun simctl install` 安装，并使用 `xcrun simctl launch --console-pty` 启动和采集日志。
先验证 CocoaPods App，再用 SPM 构建产物替换同一模拟器内的 App。两次均使用 GUI
点击页面的 **Run TCP smoke test**，地址 `127.0.0.1:9100`，检查最终页面成功消息。
调用链为页面 JS → Capacitor 原生桥 → Network.framework → Node TCP server；未使用 socket mock 或 WebSocket。

| 场景 | 两种 App 的实际结果 |
| --- | --- |
| 两次连续 UTF-8 | 原样返回 `first echo`、`second echo` |
| Hex | 原样返回 `00017fff` |
| Base64 | 原样返回 `AAEC/w==` |
| 一次发送，多次短读 | 依次返回 `buff`、`ered`、`-rea`、`d-re`、`gres`、`sion`，重组为 `buffered-read-regression` |
| 1 秒无数据超时 | 返回空串，连接可继续使用 |
| 超时后发送延迟数据 | 服务器延迟 3 秒回显，读取返回 `DELAY\n` |
| 对端关闭 | `read` 以 `code: EOF` 拒绝，这是预期断言 |
| 清理 | `disconnect` 成功返回 `client: 0` |

CocoaPods 首次 GUI 验证在 19:45:35 通过；为保存完整日志重新启动后于 19:46 再次通过。
SPM GUI 验证在 19:46:57 通过。页面日志显示：

```text
Smoke test passed: utf8: first echo; utf8: second echo; hex: 00017fff;
base64: AAEC/w==; Repeated short reads preserve remaining bytes;
Timeout followed by delayed data; Peer close reports EOF
```

## 证据及未阻断警告

仓库内保留可复核的构建/测试结尾与原生 TCP 桥接日志摘录：

- [构建和测试结果](validation/2026-11-01/native-results.txt)
- [CocoaPods example 收发](validation/2026-11-01/cocoapods-runtime.txt)
- [SPM example 收发](validation/2026-11-01/spm-runtime.txt)

完整原始日志、DerivedData、两份 `.xcresult` 位于本机临时目录
`/private/tmp/tcp-socket-validation-20261101/`，可能被系统清理；未将大体积产物加入仓库。
完整日志文件为 `cocoapods-sync.log`、`cocoapods-build.log`、`spm-build.log`、
`plugin-pod-install.log`、`pods-tests.log`、`spm-tests.log`、
`cocoapods-example-runtime.log`、`spm-example-runtime.log`。

构建及测试成功不代表零警告：Swift 6.4 提示 `TcpConnection` 嵌套闭包的 weak / strong 捕获差异；
Capacitor / Camera 也有捕获相关警告。另有 AppIntents 元数据跳过、Pods 脚本输出、
XCTest 动态库最低版本、模拟器 Network / WebKit 辅助功能日志。本次保留原状，未为消除警告扩大修改范围。
`npm ci` 审计报告根项目 15 项（6 moderate、9 high）、example 9 项（1 moderate、8 high）；
本次未进行依赖安全升级。
