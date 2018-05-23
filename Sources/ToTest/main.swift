
import Fuzzer
import ModuleToTest

struct Pair {
    let a: Int
    let b: Int
}

extension Pair: FuzzInput {
    public init(_ rand: inout Rand) {
        self.a = rand.int()
        self.b = rand.int()
    }
    
    public func complexity() -> Int {
        return 1
    }
    public func hash() -> DoubleWidthInt {
        return DoubleWidthInt(a: a, b: b)
    }
}

struct FT: FuzzTarget {
    typealias Input = Pair
    func run(_ p: Pair) -> Int {
        /*
        switch p.a % 8 {
        case 0: noop(0)
        case 1: noop(1)
        case 2: noop(3)
        case 3: noop(7)
        case 4: noop(9)
        case 5: noop(4)
        case 6: noop(18)
        case 7: noop(2)
        default:
            noop(67)
        }
        */
        print(p.a, p.b)
        if p.a < p.b {
            noop(p.b - p.a)
            return 0
        } else {
            return 1
        }
    }
}
