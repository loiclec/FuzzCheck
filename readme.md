# FuzzCheck

FuzzCheck is a coverage-guided fuzzer engine for Swift packages. 

Given a test function `(T) -> Bool`, it tries to find values of `T` that will trigger edge cases in your code. 

FuzzCheck was originally a copy of LLVM’s libFuzzer, but it has changed significantly since then. The main difference with libFuzzer is that FuzzCheck works with typed values instead of raw binary buffers, which makes it easier to test complex structured data. 

However, it is still a young and experimental project. Because FuzzCheck is a Swift package itself, it is easier to modify than libFuzzer. If you would like to contribute to it, I am happy to guide you through the code. You can contact me at loiclecrenier at icloud dot com. 

## Installation

You can install FuzzCheck by adding it as a dependency of your Swift package:
```swift
dependencies: [
	.package(url: "https://github.com/loiclec/FuzzCheck.git", from: Version(0, 1, 0))
]
```

But unfortunately, it is not the only thing you need to do in order to use it. FuzzCheck only works when the `fuzzer` sanitizer is enabled for the targets that you wish to test. Moreover, this sanitizer is only available on development snapshots of Swift. Therefore, you will need to install a Swift 4.2 Development Snapshot and to compile your package with a modified version of the Swift Package Manager. It is easier than it sounds like, here are the step-by-step instructions to do so:

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

I have created a sample project called `FuzzTestExample` that you can use to get familiar with FuzzCheck. But before explaining how it works, let's try to launch it and finally see some results!

```bash
git clone https://github.com/loiclec/FuzzTestExample
cd FuzzTestExample
# Use the swift-build executable from the modified SwiftPM and use the fuzz-release configuration
../swift-package-manager/.build/x86_64-apple-macosx10.10/debug/swift-build -c fuzz-release
# launch FuzzCheckTool with the test target as argument and the randomness seed 0
.build/fuzz-release/FuzzCheckTool --target FuzzTestExample --seed 0
```
After a few seconds, the process will stop:
```
...
...
NEW     526440  cov: 23 score: 132.0    corp: 82        exec/s: 81946   rss: 8
NEW     531935  cov: 23 score: 133.0    corp: 83        exec/s: 81900   rss: 8
NEW     535455  cov: 23 score: 134.0    corp: 84        exec/s: 81877   rss: 8

================ TEST FAILED ================
540659  cov: 23 score: 134.0    corp: 84        exec/s: 81814   rss: 8
Saving crash at /Users/loic/Projects/fuzzcheck-example/2e8d4c4a6c6f52573
```
It detected a test failure after 540659 iterations, and it saved the JSON-encoded crashing input inside the file `2e8d4c4a6c6f52573`. Half a million iterations might seem like a lot, but if the test used a simple exhaustive search, it would have *never* found that test failure, even after trillions of iterations.

### The Package.swift manifest

In your Package.swift manifest, you need to add `FuzzCheck` as a dependency, and to specify the list of targets that you wish to fuzz-test, and to create a test example. For example:

```swift
// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "FuzzTestExample",
    products: [
        .library(name: "Graph", targets: ["Graph"]),
        .executable(name: "FuzzTestExample", targets: ["FuzzTestExample"])
    ],
    dependencies: [
        .package(url: "https://github.com/loiclec/FuzzCheck.git", from: Version(0, 1, 0))
    ],
    targets: [
        .target(name: "FuzzTestExample", dependencies: [
            "FuzzCheck",
            "FuzzCheckTool", 
            "GraphFuzzUnitGenerator", 
            "Graph"
        ]),
        .target(name: "GraphFuzzUnitGenerator", dependencies: ["FuzzCheck", "Graph"]),
        .target(name: "Graph", dependencies: [])
        
    ],
    fuzzedTargets: [
     	"FuzzTestExample",
        "Graph"
    ]
)
```

This is a `Package.swift` file for a library that implements a graph data structure. It contains one fuzz test called `FuzzTestExample`, added as a product executable. It has a `FuzzCheck` dependency and specifies the name of the targets that need to be instrumented for fuzz-testing with the argument `fuzzedTargets`. We will see later what `GraphFuzzUnitGenerator` is.

The test itself is located inside `Sources/FuzzTestExample/main.swift`:
```swift
import FuzzCheck
import GraphFuzzUnitGenerator
import Graph

func test0(_ g: Graph<UInt8>) -> Bool {
    if
        g.count == 8,
        g.graph[0].data == 100,
        g.graph[1].data == 89,
        g.graph[2].data == 10,
        g.graph[3].data == 210,
        g.graph[4].data == 1,
        g.graph[5].data == 210,
        g.graph[6].data == 9,
        g.graph[7].data == 17,
        g.graph[0].edges.count == 2,
        g.graph[0].edges[0] == 1,
        g.graph[0].edges[1] == 2,
        g.graph[1].edges.count == 2,
        g.graph[1].edges[0] == 3,
        g.graph[1].edges[1] == 4,
        g.graph[2].edges.count == 2,
        g.graph[2].edges[0] == 5,
        g.graph[2].edges[1] == 6,
        g.graph[3].edges.count == 1,
        g.graph[3].edges[0] == 7,
        g.graph[4].edges.count == 0,
        g.graph[5].edges.count == 0,
        g.graph[6].edges.count == 0,
        g.graph[7].edges.count == 0
    {
        return false
    }
    return true
}

try CommandLineFuzzer.launch(test: test0, generator: GraphGenerator())
```

It is a silly test that only fails when the graph is exactly this:
```
draw an ascii graph here
```

Without passing on any special knowledge to the fuzzer about the test, it was able to find this graph in less than 1_000_000 iterations! This is impressive considering that merely finding the 8 values of its vertices would take an average of `256^7 ~= 70_000_000_000_000_000` iterations by a simple exhaustive search.


## Creating a fuzz test

To test a function `(T) -> Bool`, you need a `FuzzUnitGenerator` to generate values of `T`. If T is a standard type like Int, Array, or String, then a generator called `T.FuzzUnitGenerator` is provided out-of-the-box. (e.g. `Array<Int>.FuzzUnitGenerator`, String.FuzzUnitGenerator). Otherwise, you have to create it yourself. A `FuzzUnitGenerator` defines a way to generate and mutate values of type `T`.

It has three requirements:
1. a property `baseUnit` containing the simplest possible value of `T` (the empty array)
2. a property `mutators` that can slightly mutate values of `T`
3. a function to generate random values of `T` (there is a default implementation of that one based on `mutators`)

```swift
struct GraphFuzzUnitGenerator : FuzzUnitGenerator {
	typealias Mut = GraphMutators<IntegerMutators<UInt8>>
    typealias Unit = Graph<UInt8>
	
	var mutators: Mut = GraphMutators()
    
    let baseUnit: Unit = Graph()
}
```

The type of the property `mutators` must conform to `FuzzUnitMutators`.

## Design

FuzzCheck works by maintaining a pool of test inputs and ranking them using the complexity of the input and the uniqueness of the code coverage caused by `test(input)`. From that pool, it selects a high-ranking input, mutates it, and runs the test function again. If the new mutated input discovered new code paths in the binary, then it is added to the pool, otherwise, FuzzCheck tries again with a different input and mutation.

In pseudocode (the actual implementation is a bit more nuanced):
```
while true {
	var input = pool.select()
	mutators.mutate(&input)

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