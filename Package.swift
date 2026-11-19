// swift-tools-version:6.0
// Server side of Currency Converter: Vapor + Fluent (SQLite).
// The manifest lives in the repo root so the package can reach both
// src/server (sources) and tests/server (tests) — SwiftPM doesn't allow
// target paths outside the package root.
import PackageDescription

let package = Package(
    name: "CurrencyConverterServer",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.9.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.80.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "6.0.0"),
        .package(url: "https://github.com/vapor/sql-kit.git", from: "3.29.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "SQLKit", package: "sql-kit"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "src/server/App",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            path: "tests/server",
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)

var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("ExistentialAny"),
    ]
}
