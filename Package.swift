// swift-tools-version:5.9
import PackageDescription

// Тестовые фреймворки (XCTest/Testing) недоступны без полного Xcode,
// поэтому тесты чистой логики живут в исполняемом таргете chelka-selftest.
let package = Package(
    name: "Chelka",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ChelkaCore", path: "Sources/ChelkaCore"),
        .executableTarget(name: "Chelka", dependencies: ["ChelkaCore"], path: "Sources/Chelka"),
        .executableTarget(name: "chelka-selftest", dependencies: ["ChelkaCore"], path: "Sources/chelka-selftest"),
        .executableTarget(name: "chelka-mcp", dependencies: ["ChelkaCore"], path: "Sources/chelka-mcp"),
    ]
)
