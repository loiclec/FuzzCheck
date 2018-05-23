
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
        switch i % 8 {
        case 0: print(0)
        case 1: print(1)
        case 2: print(3)
        case 3: print(7)
        case 4: print(9)
        case 5: print(4)
        case 6: print(18)
        case 7: print(2)
        default:
            print(67)
        }
    }
}

print("go")
analyze(FT())

