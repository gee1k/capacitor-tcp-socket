// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapacitorTcpSocket",
    platforms: [.iOS(.v15)],
    products: [.library(name: "CapacitorTcpSocket", targets: ["TcpSocketPlugin"])],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", "7.0.0"..<"9.0.0")
    ],
    targets: [
        .target(
            name: "TcpSocketPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Plugin",
            exclude: ["Info.plist", "TcpSocketPlugin.h"]),
        .testTarget(name: "TcpSocketPluginTests", dependencies: ["TcpSocketPlugin"], path: "ios/PluginTests", exclude: ["Info.plist"])
    ]
)
