// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "FuzzCheck",
    products: [
        .library(name: "FuzzCheck", targets: ["FuzzCheck"]),
        .executable(name: "FuzzCheckTool", targets: ["FuzzCheckTool"]),
    ],
    dependencies: [
        .package(path: "swiftpm"),
        .package(url: "https://github.com/JohnSundell/Files.git", from: Version(2, 0, 0)) 
    ],
    targets: [
        .target(name: "CBuiltinsNotAvailableInSwift", dependencies: []),
        .target(name: "FuzzCheck", dependencies: ["Files", "Utility", "CBuiltinsNotAvailableInSwift"]),
        .target(name: "FuzzCheckTool", dependencies: ["Files", "FuzzCheck", "Utility"]),
        .testTarget(name: "FuzzerTests", dependencies: ["FuzzCheck"]),
    ]
)

