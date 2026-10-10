// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Mail-Filter",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "mail-filter", targets: ["MailFilter"])],
    targets: [
        .executableTarget(name: "MailFilter"),
        .testTarget(name: "MailFilterTests", dependencies: ["MailFilter"])
    ]
)
