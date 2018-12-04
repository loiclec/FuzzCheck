# FuzzCheck

FuzzCheck is a coverage-guided fuzzing engine for Swift packages that works with typed values instead of raw binary buffers. 

The name “FuzzCheck” is a mix of “Fuzzer” and “QuickCheck”. The goal is to create a fuzzing engine that is convenient enough to use as the input generator for property-based tests.

Given a test function `(Input) -> Bool`, it tries to find values of `Input` that will trigger edge cases in your code. It can also automatically minimize an input that fails a test.

Because FuzzCheck is a Swift package itself, it is easier to modify than libFuzzer. If you would like to contribute to it, I am happy to guide you through the code.

## Installation

FuzzCheck is not production ready. Using it requires both a development snapshot of the Swift compiler, and a custom build of the Swift Package Manager. That is because the compile flag `-sanitize=fuzzer` must be enabled for the tested targets. 

The good news is that once these tools are installed, FuzzCheck is just another dependency in your `Package.swift` file!

- go to [swift.org/downloads](https://swift.org/download#snapshots) and download the Swift 4.2 Development Snapshot by clicking on the “Xcode” link and following the instructions. 
- Find the path of the `swiftc` executable you just installed and assign it to the `SWIFT_EXEC` environment variable. For example, if you installed the snapshot from the 3rd of July, you should run:
  ```bash
  export SWIFT_EXEC=/Library/Developer/Toolchains/swift-4.2-DEVELOPMENT-SNAPSHOT-2018-07-03-a.xctoolchain/usr/bin/swiftc
  ```
- Clone my fork of the Swift Package Manager.
  ```bash
  git clone https://github.com/loiclec/swift-package-manager
  ``` 
- Then build it. It should not take more than a few minutes.
  ```bash
  cd swift-package-manager
  Utilities/bootstrap
  ```

That's it! You now have everything you need to use FuzzCheck!
The executables that you will need to use to compile your Swift packages are located inside `swift-package-manager/.build/x86_64-apple-macosx10.10/debug/`

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

## Using FuzzCheck

I have created a sample project called `FuzzCheckExample` that you can use to get familiar with FuzzCheck. But before explaining how it works, let's try to launch it and finally see some results!

```bash
git clone https://github.com/loiclec/FuzzCheckExample.git
cd FuzzCheckExample
# Use the swift-build executable from the modified SwiftPM and use the fuzz-release configuration
../swift-package-manager/.build/x86_64-apple-macosx10.10/debug/swift-build -c fuzz-release
# launch FuzzCheckTool with the test target as argument
.build/fuzz-release/FuzzCheckTool --target FuzzCheckExample
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

It detected a test failure after 529434 iterations, and it saved the JSON-encoded crashing input inside the file `testFailure-78a1af7b1be086ca0.json`. Half a million iterations might seem like a lot, but if the test used a simple exhaustive or random search, it would have *never* found that test failure, even after trillions of iterations.

The `Package.swift` manifest of FuzzCheckExample is:

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
        .package(url: "https://github.com/loiclec/FuzzCheck.git", .revision("b4abbf661f4d187ec88bc2811893283d4c091260"))
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

This manifest:
- has a `FuzzCheck` dependency, pinned to a specific commit (no stable version has been released yet)
- contains one fuzz-test executable called `FuzzCheckExample`. Its target depends on `FuzzCheck` and `FuzzCheckTool`.
- has a `fuzzedTargets` argument containing the targets that needs to be compiled with the `fuzzer` sanitizer
- has a `GraphFuzzerInputGenerator` target, which defines how to mutate values of type `Graph`. This is required by FuzzCheck.

The test itself is located inside `Sources/FuzzCheckExample/main.swift`:
```swift
import FuzzCheck
import GraphFuzzerInputGenerator
import Graph

func test(_ g: Graph<UInt8>) -> Bool {
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
        g.vertices[4].edges.count == 0,
        g.vertices[5].edges.count == 0,
        g.vertices[6].edges.count == 0,
        g.vertices[7].edges.count == 0
    {
        return false
    }
    return true
}

let generator = 
    GraphFuzzerInputGenerator<IntegerFuzzerGenerator<UInt8>>(
        vertexGenerator: .init()
    )

try CommandLineFuzzer.launch(
    test: test, 
    generator: generator
)

```

It is a silly test that only fails when the graph data structure given as input is equal to this:
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

Without passing on any special knowledge to the fuzzer about the test, it was able to find this graph in less than 1_000_000 iterations! This is impressive considering that merely finding the 8 values of its vertices would take an average of `256^7 ~= 70_000_000_000_000_000` iterations by a simple exhaustive or random search.

## Creating a fuzz test

To test a function `(Input) -> Bool`, you need a `FuzzerInputGenerator` to generate values of `Input`. A `FuzzerInputGenerator` has three requirements:
1. a property `baseInput` containing the simplest possible value of `Input` (e.g. the empty array)
2. a function to slightly mutate values of `Input` (e.g. append an element to an array)
3. a function to generate random values of `Input` (there is a default implementation of that one based on the `mutate` function)

```swift
public protocol FuzzerInputGenerator: FuzzerInputProperties {
    associatedtype Input

    var baseInput: Input { get }
    func initialInputs(maxComplexity: Double, _ rand: inout FuzzerPRNG) -> [Input]
    func mutate(_ input: inout Input, _ spareComplexity: Double, _ rand: inout FuzzerPRNG) -> Bool
}
```

`FuzzerInputGenerator` also conforms to `FuzzerInputProperties`, which gives the complexity of an input and its hash:
```swift
public protocol FuzzerInputProperties {
    associatedtype Input

    static func complexity(of input: Input) -> Double
    static func hash(_ input: Input, into hasher: inout Hasher)
}
```

I hope to provide many default implementations of these two protocols out-of-the-box, and to have tools to create them automatically (e.g. using Sourcery). But for now, you will have to implement them yourself.

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
- almost no FuzzerInputGenerator implementations are provided yet
- large codebases will be slow to fuzz-test. Work needs to be done to make it faster   
- some of the fundamental design and implementation details might still change

## History

FuzzCheck was originally a copy of LLVM’s libFuzzer, but it has changed significantly since then. The main differences are that FuzzCheck:
- works with typed values instead of raw binary buffers
- uses a different algorithm to rank the inputs in the pool
- is designed such that a different measure than code coverage could be used to rank the inputs in the pool
- does not support crossover mutations
- does not work with dictionaries, manual or automatic
- only works with Swift programs
- is not integrated with the address sanitizer
- is not battle-tested and has not proven itself yet
