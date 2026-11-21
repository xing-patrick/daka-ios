// swift-tools-version:5.9
import PackageDescription

// 只用于跑纯逻辑单测（数据层不依赖 UIKit / SwiftUI），
// 真机 App 由 XcodeGen 从 project.yml 生成。
let package = Package(
    name: "DakaCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "DakaCore", targets: ["DakaCore"])
    ],
    targets: [
        .target(name: "DakaCore", path: "Sources/DakaCore"),
        .testTarget(name: "DakaCoreTests", dependencies: ["DakaCore"], path: "Tests/DakaCoreTests")
    ]
)
