// swift-tools-version:5.9
import PackageDescription

// Тестовые фреймворки (XCTest/Testing) недоступны без полного Xcode,
// поэтому тесты чистой логики живут в исполняемом таргете lintel-selftest.
let package = Package(
    name: "Lintel",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "LintelCore", path: "Sources/LintelCore"),
        .executableTarget(name: "Lintel", dependencies: ["LintelCore"], path: "Sources/Lintel"),
        .executableTarget(name: "lintel-selftest", dependencies: ["LintelCore"], path: "Sources/lintel-selftest"),
        .executableTarget(name: "lintel-mcp", dependencies: ["LintelCore"], path: "Sources/lintel-mcp"),
    ]
)
