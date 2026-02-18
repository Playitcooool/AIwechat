// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIwechatMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AIwechatMac", targets: ["AIwechatMac"]),
    ],
    targets: [
        .executableTarget(
            name: "AIwechatMac",
            path: "Sources/AIwechatMac"
        )
    ]
)
