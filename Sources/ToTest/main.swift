
import CBuiltinsNotAvailableInSwift

@inline(never) func foo() -> Void {
    print(__return_address())
}

for _ in 0 ..< 3 {
    foo()
    foo()
    print("---")
}

print(__popcountll(0b1011100101110001))

/*
import Fuzzer
import ModuleToTest

extension Int: FuzzInput {
    public init(_ rand: inout Rand) {
        self = rand.int()
    }
}

struct FT: FuzzTarget {
    typealias Input = Int
    func run(_ i: Int) {
        if i % 2 == i % 3 {
            print(i)
        } else {
            print(bar(i) + 1)
        }
    }
}

analyze(FT())
*/
