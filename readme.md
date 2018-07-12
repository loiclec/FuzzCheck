# FuzzCheck

FuzzCheck is a coverage-guided fuzzing engine for Swift packages. 

The name “FuzzCheck” is a mix of “Fuzzer” and “QuickCheck”. The goal is to create a fuzzing engine that is convenient enough to use as the value generator powering property-based tests.

Given a test function `(T) -> Bool`, it tries to find values of `T` that will trigger edge cases in your code. It can also automatically minimize an input that fails a test.

FuzzCheck was originally a copy of LLVM’s libFuzzer, but it has changed significantly since then. The main difference with libFuzzer is that FuzzCheck works with typed values instead of raw binary buffers, which makes it easier to test complex structured data. However, it is still a young and experimental project. 

Because FuzzCheck is a Swift package itself, it is easier to modify than libFuzzer. If you would like to contribute to it, I am happy to guide you through the code.

## Installation

FuzzCheck only works when the `fuzzer` sanitizer is enabled for the targets that you wish to test. Moreover, this sanitizer is only available on development snapshots of Swift. Therefore, you will need to install a Swift 4.2 Development Snapshot and to compile your package with a modified version of the Swift Package Manager. It is easier than it sounds, here are the step-by-step instructions to do so:

- go to [swift.org/downloads](https://swift.org/download#snapshots) and download the Swift 4.2 Development Snapshot by clicking on the “Xcode” link and following the instructions. 
- Find the path of the `swiftc` executable you just installed and assign it to the `SWIFT_EXEC` environment variable. For example, if you installed the snapshot from the 3rd of July, you should run:
  ```bash
  export SWIFT_EXEC=/Library/Developer/Toolchains/swift-4.2-DEVELOPMENT-SNAPSHOT-2018-07-03-a.xctoolchain/usr/bin/swiftc
  ```
  This is needed to build the Swift Package Manager.
- Clone my fork of the Swift Package Manager.
  ```bash
  git clone https://github.com/loiclec/swift-package-manager
  ``` 
- Then build it. It should not take more than a few minutes.
  ```bash
  cd swift-package-manager
  Utilities/bootstrap
  ```
- If everything went well, it created a few executables inside `.build/x86_64-apple-macosx10.10/debug/`.
  ```bash
  # swiftc: verify that its version contains `Apple Swift version 4.2-dev`
  .build/x86_64-apple-macosx10.10/debug/swiftc --version
  Apple Swift version 4.2-dev (LLVM 647959670b, Clang 8756d7b836, Swift 107e307eae)
  Target: x86_64-apple-darwin18.0.0

  # swift-build replaces `swift build`
  .build/x86_64-apple-macosx10.10/debug/swift-build --version
  Swift Package Manager - Swift 4.2.0
  
  # swift-package replaces `swift package`
  .build/x86_64-apple-macosx10.10/debug/swift-package --version

  Swift Package Manager - Swift 4.2.0
  ```
- That's it! You have everything you need to use FuzzCheck!

The version of SwiftPM that you built adds the ability to specify a `fuzzedTargets` property in the `Package.swift` manifest. This property should contain the names of the targets that you wish to fuzz-test. It also adds the `fuzz-debug` and `fuzz-release` configuration options.

## Using FuzzCheck

I have created a sample project called `FuzzCheckExample` that you can use to get familiar with FuzzCheck. But before explaining how it works, let's try to launch it and finally see some results!

```bash
git clone https://github.com/loiclec/FuzzCheckExample.git
cd FuzzCheckExample
# Use the swift-build executable from the modified SwiftPM and use the fuzz-release configuration
../swift-package-manager/.build/x86_64-apple-macosx10.10/debug/swift-build -c fuzz-release
# launch FuzzCheckTool with the test target as argument and the randomness seed 1
.build/fuzz-release/FuzzCheckTool --target FuzzCheckExample --seed 1
```
After a few seconds, the process will stop:
```
...
...
DELETE 1
NEW     528502  score: 122.0    corp: 81        exec/s: 103402  rss: 8
DELETE 1
NEW     528742  score: 122.0    corp: 81        exec/s: 103374  rss: 8

================ TEST FAILED ================
529434  score: 122.0    corp: 81        exec/s: 103374  rss: 8
Saving testFailure at /Users/loic/Projects/fuzzcheck-example/artifacts/testFailure-78a1af7b1be086ca0.json
```
It detected a test failure after 529434 iterations, and it saved the JSON-encoded crashing input inside the file `testFailure-78a1af7b1be086ca0.json`. Half a million iterations might seem like a lot, but if the test used a simple exhaustive search, it would have *never* found that test failure, even after trillions of iterations.

### The Package.swift manifest

In your Package.swift manifest, you need to add `FuzzCheck` as a dependency and to specify the list of targets that you wish to fuzz-test. For example:

```swift
// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "FuzzCheckExample",
    products: [
        .library(name: "Graph", targets: ["Graph"]),
        .executable(name: "FuzzCheckExample", targets: ["FuzzCheckExample"])
    ],
    dependencies: [
        .package(url: "https://github.com/loiclec/FuzzCheck.git", .revision("e20fad2beae3dd1eb003aa6a4813cec2006078b4"))
    ],
    targets: [
        .target(name: "FuzzCheckExample", dependencies: [
            "FuzzCheck",
            "FuzzCheckTool", 
            "GraphFuzzerInputGenerator", 
            "Graph"
        ]),
        .target(name: "GraphFuzzerInputGenerator", dependencies: ["FuzzCheck", "Graph"]),
        .target(name: "Graph", dependencies: [])
    ],
    fuzzedTargets: [
        "FuzzCheckExample",
        "Graph"
    ]
)

```

This is a `Package.swift` file for a library that implements a graph data structure. It contains one fuzz test called `FuzzCheckExample`, added as a product executable. It has a `FuzzCheck` dependency and specifies the name of the targets that need to be instrumented for fuzz-testing with the argument `fuzzedTargets`. We will see later what `GraphFuzzerInputGenerator` is.

The test itself is located inside `Sources/FuzzCheckExample/main.swift`:
```swift
import FuzzCheck
import GraphFuzzerInputGenerator
import Graph

func test0(_ g: Graph<UInt8>) -> Bool {
    if
        g.count == 8,
        g.vertices[0].data == 100,
        g.vertices[1].data == 89,
        g.vertices[2].data == 10,
        g.vertices[3].data == 210,
        g.vertices[4].data == 1,
        g.vertices[5].data == 210,
        g.vertices[6].data == 9,
        g.vertices[7].data == 17,
        g.vertices[0].edges.count == 2,
        g.vertices[0].edges[0] == 1,
        g.vertices[0].edges[1] == 2,
        g.vertices[1].edges.count == 2,
        g.vertices[1].edges[0] == 3,
        g.vertices[1].edges[1] == 4,
        g.vertices[2].edges.count == 2,
        g.vertices[2].edges[0] == 5,
        g.vertices[2].edges[1] == 6,
        g.vertices[3].edges.count == 1,
        g.vertices[3].edges[0] == 7,
        g.vertices[5].edges.count == 0,
        g.vertices[6].edges.count == 0,
        g.vertices[7].edges.count == 0
    {
        return false
    }
    return true
}

typealias UInt8Fuzzing = IntegerFuzzing<UInt8>

try CommandLineFuzzer.launch(
    test: test0, 
    generator: GraphFuzzerInputGenerator<UInt8Fuzzing>(vertexGenerator: .init()), 
    properties: GraphFuzzerInputProperties<UInt8Fuzzing>.self
)

```

It is a silly test that only fails when the graph is equal to this:
```
             ┌─────┐            
             │ 100 │            
             └─┬─┬─┘            
        ┌──────┘ └──────┐       
     ┌──▼──┐         ┌──▼──┐    
     │ 89  │         │ 10  │    
     └──┬──┘         └──┬──┘    
   ┌────┴───┐       ┌───┴───┐   
┌──▼──┐  ┌──▼──┐ ┌──▼──┐ ┌──▼──┐
│ 210 │  │  1  │ │ 210 │ │  9  │
└──┬──┘  └─────┘ └─────┘ └─────┘
   │                            
┌──▼──┐                         
│ 17  │                         
└─────┘                         
```

Without passing on any special knowledge to the fuzzer about the test, it was able to find this graph in less than 1_000_000 iterations! This is impressive considering that merely finding the 8 values of its vertices would take an average of `256^7 ~= 70_000_000_000_000_000` iterations by a simple exhaustive search.


## Creating a fuzz test

To test a function `(T) -> Bool`, you need a `FuzzerInputGenerator` to generate values of `T`. A `FuzzerInputGenerator` has three requirements:
1. a property `baseInput` containing the simplest possible value of `T` (e.g. the empty array)
2. a function to slightly mutate values of `T` (e.g. append an element to an array)
3. a function to generate random values of `T` (there is a default implementation of that one based on the mutate function)

```swift
/// A protocol defining how to generate and mutate values of type Input.
public protocol FuzzerInputGenerator {

    associatedtype Input

    var baseInput: Input { get }
  
    func initialInputs(_ rand: inout FuzzerPRNG) -> [Input]

    func mutate(_ input: inout Input, _ rand: inout FuzzerPRNG) -> Bool
}
```

You also need a `FuzzerInputProperties` type, which gives the complexity of an input and its hash:
```swift
public protocol FuzzerInputProperties {
    associatedtype Input

    static func complexity(of input: Input) -> Double    
    static func hash(of input: Input) -> Int
}
```

## Design

FuzzCheck works by maintaining a pool of test inputs and ranking them using the complexity of the input and the uniqueness of the code coverage caused by `test(input)`. From that pool, it selects a high-ranking input, mutates it, and runs the test function again. If the new mutated input discovered new code paths in the binary, then it is added to the pool, otherwise, FuzzCheck tries again with a different input and mutation.

In pseudocode (the actual implementation is a bit more nuanced):
```
while true {
    var input = pool.select()
    mutate(&input)

    let analysis = analyze { test(input) }

    switch analysis {
    case .crashed, .failed:
        return reportFailure(input)
    case .interesting(let score):
        pool.add(input, score)
    case .notInteresting:
        continue
    }
}
```

## Caveats

- tests that use more than one thread are not supported (but should be in the future)
- almost no FuzzInputGenerator implementations are provided yet
- large codebases will be slow to fuzz-test. Work needs to be done to make it faster   
- some of the fundamental design and implementation details might still change