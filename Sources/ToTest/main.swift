
import Basic
import Foundation
import Fuzzer
import ModuleToTest
import ModuleToTestMutators
import Utility

struct Nothing: Hashable { }
extension Nothing: FuzzUnit {
    func complexity() -> Complexity {
        return 1.0
    }
    func hash() -> Int {
        return 0.hashValue
    }
}
struct NothingMutators: Mutators {
    func mutate(_ unit: inout Nothing, with mutator: Void, _ rand: inout Rand) -> Bool { return false }
    let weightedMutators: [(Mutator, UInt64)] = []
    typealias Mutated = Nothing
    typealias Mutator = Void
}

extension UInt8: FuzzUnit { }

struct FT : FuzzTest {
    typealias Unit = Graph<UInt8>
    //typealias Unit = Graph<Nothing>
    typealias Mut = GraphMutators<UnsignedIntegerMutators<UInt8>>
    
    var mutators: FT.Mut = GraphMutators(vertexMutators: UnsignedIntegerMutators.init(), initializeVertex: { r in r.byte() })
    //var mutators: FT.Mut = GraphMutators(vertexMutators: NothingMutators(), initializeVertex: { r in Nothing() })
    
    static func baseUnit() -> Unit {
        return Graph()
    }
    
    func newUnit(_ r: inout Rand) -> Unit {
        var g = Graph<UInt8>()
        //var g = Graph<Nothing>()
        for _ in 0 ..< r.positiveInt(10) {
            _ = graphMutators.mutate(&g, &r)
        }
        return g
    }
    
    func run(_ g: Unit) {
        /*
        let comp = g.stronglyConnectedComponents()
        if comp.count > 3,
            comp[0].count >= 3,
            comp[1].count >= 3,
            comp[2].count >= 3
        {
            fatalError()
        }
         */
        //g.crashIfCyclic()
        /*
        if
            g.count == 10,
            g.graph[0].data == 0x64,
            g.graph[1].data == 0x65,
            g.graph[2].data == 0x61,
            g.graph[3].data == 0x64,
            g.graph[4].data == 0x62,
            g.graph[5].data == 0x65,
            g.graph[6].data == 0x65,
            g.graph[7].data == 0x67,
            g.graph[8].data == 0x68,
            g.graph[9].data == 0x69,
            g.graph[0].edges.count == 2,
            g.graph[0].edges[0] == 1,
            g.graph[0].edges[1] == 2,
            g.graph[1].edges.count == 2,
            g.graph[1].edges[0] == 3,
            g.graph[1].edges[1] == 4,
            g.graph[2].edges.count == 2,
            g.graph[2].edges[0] == 5,
            g.graph[2].edges[1] == 6,
            g.graph[3].edges.count == 2,
            g.graph[3].edges[0] == 7,
            g.graph[3].edges[1] == 8,
            g.graph[4].edges.count == 1,
            g.graph[4].edges[0] == 9,
            g.graph[5].edges.count == 0,
            g.graph[6].edges.count == 0,
            g.graph[7].edges.count == 0,
            g.graph[8].edges.count == 0,
            g.graph[9].edges.count == 0
        {
            fatalError()
        }
        */
        if
            g.count == 6,
            g.graph[0].data == 0x64,
            g.graph[1].data == 0x65,
            g.graph[2].data == 0x61,
            g.graph[3].data == 0x64,
            g.graph[4].data == 0x62,
            g.graph[5].data == 0x65,
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
        }
    }
}

let graphMutators = GraphMutators(vertexMutators: UnsignedIntegerMutators<UInt8>(), initializeVertex: { r in r.byte() })

let (parser, settingsBinder, worldBinder, _) = CommandLineFuzzerWorldInfo.argumentsParser()
do {
    let res = try parser.parse(Array(CommandLine.arguments.dropFirst()))
    var settings: FuzzerSettings = FuzzerSettings()
    try settingsBinder.fill(parseResult: res, into: &settings)
    var world: CommandLineFuzzerWorldInfo = CommandLineFuzzerWorldInfo()
    try worldBinder.fill(parseResult: res, into: &world)
    
    print(settings)
    print(world)
    
    let fuzzer = Fuzzer(fuzzTest: FT(), settings: settings, world: CommandLineFuzzerWorld(info: world))
    if settings.minimize {
        fuzzer.minimizeLoop()
    } else {
        fuzzer.loop()
    }
} catch let e {
    print(e)
    parser.printUsage(on: stdoutStream)
}
