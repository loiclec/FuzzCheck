import Foundation
import Fuzzer
import ModuleToTest
import ModuleToTestMutators

extension UInt8: FuzzInput { }

struct FT : FuzzTest {
    typealias Unit = Graph<UInt8>
    typealias Mut = GraphMutators
    
    var mutators: FT.Mut = GraphMutators.init(vertexMutators: UnsignedIntegerMutators.init(), initializeVertex: { r in r.byte() })
    
    static func baseUnit() -> Unit {
        return Graph()
    }
    
    func newUnit(_ r: inout Rand) -> Unit {
        var g = Graph<UInt8>()
        for _ in 0 ..< r.positiveInt(10) {
            _ = graphMutators.mutate(&g, &r)
        }
        return g
    }
    
    func run(_ g: Unit) {
        if
            g.count == 8,
            g.graph[0].data == 0x64,
            g.graph[1].data == 0x65,
            g.graph[2].data == 0x61,
            g.graph[3].data == 0x64,
            g.graph[4].data == 0x62,
            g.graph[5].data == 0x65,
            g.graph[6].data == 0x65,
            g.graph[7].data == 0x67,
            g.graph[0].edges.count == 2,
            g.graph[0].edges[0] == 1,
            g.graph[0].edges[1] == 2,
            g.graph[1].edges.count == 2,
            g.graph[1].edges[0] == 3,
            g.graph[1].edges[1] == 4,
            case () = print(",", terminator: ""),
            g.graph[2].edges.count == 2,
            g.graph[2].edges[0] == 5,
            g.graph[2].edges[1] == 6,
            case () = print("|", terminator: ""),
            g.graph[3].edges.count == 1,
            g.graph[3].edges[0] == 7,
            g.graph[4].edges.count == 0,
            g.graph[5].edges.count == 0
        {
            fatalError()
        }
    }
}

let graphMutators = GraphMutators(vertexMutators: UnsignedIntegerMutators<UInt8>(), initializeVertex: { r in r.byte() })

let seed = CommandLine.arguments.count > 1 ? UInt32(CommandLine.arguments[1])! : UInt32(time(nil))

var fuzzer = Fuzzer(fuzzTarget: FT(), seed: seed)
fuzzer.loop()






