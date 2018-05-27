// swift-tools-version:4.1
import PackageDescription

let package = Package(
    name: "swiftpm-fuzzed",
    products: [
        // .library(name: "ModuleToTest", targets: ["ModuleToTest"]),
        // .library(name: "Fuzzer", targets: ["Fuzzer"]),
        .executable(name: "ToTest", targets: ["ToTest"]),
        // .fuzzTest(name: "ToTest", target: ["ToTest"], fuzzedTargets: ["ToTest", "ModuleToTest"])
    ],
    dependencies: [],
    targets: [
        .target(name: "CBuiltinsNotAvailableInSwift", dependencies: []),
        .target(name: "Fuzzer", dependencies: ["CBuiltinsNotAvailableInSwift"]),
        .target(name: "ModuleToTest", dependencies: []),
        .target(name: "ModuleToTestMutators", dependencies: ["Fuzzer", "ModuleToTest"]),
        .target(name: "ToTest", dependencies: ["Fuzzer", "ModuleToTest", "ModuleToTestMutators"]),

        .testTarget(name: "FuzzerTests", dependencies: ["Fuzzer"])
    ]
)

