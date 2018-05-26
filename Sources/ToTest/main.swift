import Foundation
import Fuzzer
//import ModuleToTest
//import ModuleToTestMutators
/*
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
*/
/*
 
extension UInt8: FuzzInput { }

struct FT : FuzzTarget {
    typealias Input = Graph<UInt8>
    
    static func baseInput() -> Graph<UInt8> {
        return Graph.init()
    }
    
    func newInput(_ r: inout Rand) -> Graph<UInt8> {
        var g = Graph<UInt8>()
        let count = r.positiveInt(8)
        for _ in 0 ..< count {
            _ = graphMutators.mutate(&g, &r)
        }
        return g
    }
    
    func run(_ g: Graph<UInt8>) -> Int {
        /*
        if
            g.count == 6,
            g.graph[0].data == 0x64,
            g.graph[1].data == 0x65,
            g.graph[2].data == 0x61,
            g.graph[3].data == 0x64,
            g.graph[4].data == 0x62,
            g.graph[5].data == 0x65,
            case () = print("done"),
            g.graph[0].edges.count == 2,
            g.graph[0].edges[0] == 1,
            g.graph[0].edges[1] == 2,
            g.graph[1].edges.count == 2,
            g.graph[1].edges[0] == 3,
            g.graph[1].edges[1] == 4,
            g.graph[2].edges.count == 1,
            g.graph[2].edges[0] == 5,
            g.graph[3].edges.count == 0,
            g.graph[4].edges.count == 0,
            g.graph[5].edges.count == 0
        {
            fatalError()
        }*/
        return 0
    }
}

let graphMutators = GraphMutators(vertexMutators: UnsignedIntegerMutators<UInt8>(), initializeVertex: { r in r.byte() })

let fuzzer = Fuzzer(mutators: graphMutators, fuzzTarget: FT())

fuzzer.loop(["Corpus"])
*/

struct FT : FuzzTarget {
    typealias Input = IntWrapper
    
    static func baseInput() -> Input {
        return IntWrapper.init(x: 0)
    }
    
    func newInput(_ r: inout Rand) -> Input {
        return IntWrapper.init(x: r.int())
    }
    
    func run(_ g: Input) -> Int {

        if
            g.x < 500,
            g.x > 0,
            g.x > 1,
            noop(g.x),
            g.x > 2,
            noop(g.x),
            g.x > 5,
            noop(g.x),
            g.x > 10,
            noop(g.x),
            g.x > 11,
            noop(g.x),
            g.x > 20,
            noop(g.x),
            g.x > 30,
            noop(g.x),
            g.x > 40,
            noop(g.x),
            g.x > 50,
            noop(g.x),
            g.x > 60,
            noop(g.x),
            g.x > 70,
            noop(g.x),
            g.x > 80,
            noop(g.x),
            g.x > 100,
            noop(g.x),
            g.x > 110,
            noop(g.x),
            g.x > 120,
            noop(g.x),
            g.x > 130,
            noop(g.x),
            g.x > 140,
            noop(g.x),
            g.x > 150,
            noop(g.x),
            g.x > 160,
            noop(g.x),
            g.x > 170,
            noop(g.x),
            g.x > 180,
            noop(g.x),
            g.x > 190,
            noop(g.x),
            g.x > 200,
            noop(g.x),
            g.x > 210,
            noop(g.x),
             g.x > 220,
            noop(g.x),
             g.x > 230,
            noop(g.x),
            g.x > 240,
            noop(g.x),
            g.x > 250,
            noop(g.x),
            g.x > 260,
            noop(g.x),
            g.x > 270,
            noop(g.x),
            g.x > 280,
            noop(g.x),
            g.x > 290,
            noop(g.x),
            g.x > 300,
            noop(g.x),
            g.x > 310
        {
            fatalError()
        }

        return 0
        /*
         if
         g.count == 6,
         g.graph[0].data == 0x64,
         g.graph[1].data == 0x65,
         g.graph[2].data == 0x61,
         g.graph[3].data == 0x64,
         g.graph[4].data == 0x62,
         g.graph[5].data == 0x65,
         case () = print("done"),
         g.graph[0].edges.count == 2,
         g.graph[0].edges[0] == 1,
         g.graph[0].edges[1] == 2,
         g.graph[1].edges.count == 2,
         g.graph[1].edges[0] == 3,
         g.graph[1].edges[1] == 4,
         g.graph[2].edges.count == 1,
         g.graph[2].edges[0] == 5,
         g.graph[3].edges.count == 0,
         g.graph[4].edges.count == 0,
         g.graph[5].edges.count == 0
         {
         fatalError()
         }*/
        //return 0
    }
}

// let graphMutators = GraphMutators(vertexMutators: UnsignedIntegerMutators<UInt8>(), initializeVertex: { r in r.byte() })

let fuzzer = Fuzzer(mutators: IntWrapperMutators(), fuzzTarget: FT())

fuzzer.loop(["Corpus"])

