
import Basic
import DefaultFuzzUnitGenerators
import Foundation
import Fuzzer
import ModuleToTest
import ModuleToTestMutators
import Utility

func test(_ g: Graph<UInt8>) -> Bool {
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
        return false
     }
     else {
        return true
    }
}

try CommandLineFuzzer.launch(test: test, generator: GraphGenerator())
