// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SaneVideoTools",
    dependencies: [
        .package(url: "https://github.com/danger/swift.git", from: "3.20.0")
    ],
    targets: [
        .executableTarget(
            name: "SaneVideoTools",
            dependencies: [
                .product(name: "Danger", package: "swift")
            ],
            path: "Scripts/Tools"
        )
    ]
)
