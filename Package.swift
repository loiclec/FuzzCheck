// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "FuzzCheck",
    products: [
        .library(name: "FuzzCheck", targets: ["Fuzzer", "DefaultFuzzUnitGenerators"]),
        .executable(name: "FuzzCheckTool", targets: ["FuzzerJobsManager"]),
    ],
    dependencies: [
        .package(path: "swiftpm"),
        .package(url: "https://github.com/JohnSundell/Files.git", from: Version(2, 0, 0)) 
    ],
    targets: [
        .target(name: "CBuiltinsNotAvailableInSwift", dependencies: []),
        .target(name: "Fuzzer", dependencies: ["Files", "Utility", "CBuiltinsNotAvailableInSwift"]),
        .target(name: "FuzzerJobsManager", dependencies: ["Files", "Fuzzer", "Utility"]),
        .target(name: "DefaultFuzzUnitGenerators", dependencies: ["Fuzzer"]),
        .testTarget(name: "FuzzerTests", dependencies: ["Fuzzer"]),
    ]
)

