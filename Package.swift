// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LnxClient",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "LnxClient", targets: ["LnxClient"])],
    dependencies: [.package(url: "https://github.com/chronista-club/club-unison.git", from: "2.3.0")],
    targets: [
        .target(
            name: "LnxClient",
            dependencies: [.product(name: "UnisonClient", package: "club-unison")],
            path: "clients/swift/Sources/LnxClient"
        ),
        .testTarget(
            name: "LnxClientTests",
            dependencies: ["LnxClient"],
            path: "clients/swift/Tests/LnxClientTests"
        ),
    ]
)
