// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "swiftpm-fuzzed",
    products: [
        .library(name: "ModuleToTest", targets: ["ModuleToTest"]),
        .library(name: "Fuzzer", targets: ["Fuzzer"]),
        .executable(name: "ToTest", targets: ["ToTest"]),
        .executable(name: "ReadGraph", targets: ["ReadGraph"]), 
        .executable(name: "FuzzerJobsManager", targets: ["FuzzerJobsManager"]),
    ],
    dependencies: [
        .package(path: "swiftpm"),
        .package(url: "https://github.com/JohnSundell/Files.git", from: Version(2, 0, 0)) 
    ],
    targets: [
        .target(name: "CBuiltinsNotAvailableInSwift", dependencies: []),
        .target(name: "Fuzzer", dependencies: ["Files", "Utility", "CBuiltinsNotAvailableInSwift"]),
        .target(name: "FuzzerJobsManager", dependencies: ["Fuzzer", "Utility"]),
        .target(name: "ModuleToTest", dependencies: []),
        .target(name: "ModuleToTestMutators", dependencies: ["Fuzzer", "ModuleToTest"]),
        .target(name: "ToTest", dependencies: ["Fuzzer", "ModuleToTest", "ModuleToTestMutators", "Utility"]),
        .target(name: "ReadGraph", dependencies: ["ModuleToTest", "ModuleToTestMutators"]),
        .testTarget(name: "FuzzerTests", dependencies: ["Fuzzer"])
    ],
    fuzzedTargets: ["ToTest", "ModuleToTest"]
)

