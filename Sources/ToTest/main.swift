
import Fuzzer
import ModuleToTest

struct Pair: Codable {
    var a: Int
    var b: Int
}

struct PairMutators: Mutators {
    typealias Mutated = Pair
    
    public func a(_ x: inout Pair, _ r: inout Rand) -> Bool {
        return IntMutators().mutate(&x.a, &r)
    }
    public func b(_ x: inout Pair, _ r: inout Rand) -> Bool {
        return IntMutators().mutate(&x.b, &r)
    }
    
    
    func weightedMutators(for x: Mutated) -> [((inout Mutated, inout Rand) -> Bool, UInt64)] {
        return [
            (self.a, 1),
            (self.b, 1)
        ]
    }
}

extension Pair: FuzzInput {
    public func complexity() -> Double {
        return 2
    }
    public func hash() -> Int {
        return a.hashValue &* 65371 ^ b.hashValue
    }
}

let arrayPairMutators = ArrayMutators(initializeElement: { r in Pair.init(a: r.int(), b: r.int()) }, elementMutators: PairMutators())

struct FT: FuzzTarget {
    typealias Input = Array<Pair>

    static func baseInput() -> Input {
        return []
    }
    
    func newInput(_ r: inout Rand) -> Input {
        var x: Input = []
        _ = arrayPairMutators.replaceCompletely(&x, &r)
        return x
    }
    
    func run(_ a: Input) -> Int {
        // switch p.a % 8 {
        // case 0: noop(0)
        // case 1: noop(1)
        // case 2: noop(3)
        // case 3: noop(7)
        // case 4: noop(9)
        // case 5: noop(4)
        // case 6: noop(18)
        // case 7: noop(2)
        // default:
        //     noop(67)
        // }
        // return 0
        for p in a {
            if p.a < p.b {
                noop(3)
            } else if p.a == p.b &+ 3 {
                noop(5)
            } else if p.a > p.b {
                noop(9)
            } else {
                let c = p.b &- p.a
                if a.count == c + p.b {
                    fatalError()
                }
            }
        }
        return 0
    }
}

let fuzzer = Fuzzer(mutators: arrayPairMutators, fuzzTarget: FT())

fuzzer.loop(["Corpus"])

