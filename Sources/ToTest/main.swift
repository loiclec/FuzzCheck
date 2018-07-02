
import Basic
import DefaultFuzzUnitGenerators
import Foundation
import Fuzzer
import ModuleToTest
import ModuleToTestMutators
import Utility

func test0(_ g: Graph<UInt8>) -> Bool {
    if
        g.count == 8,
        g.graph[0].data == 0x64,
        g.graph[1].data == 0x65,
        g.graph[2].data == 0x61,
        g.graph[3].data == 0x64,
        g.graph[4].data == 0x62,
        g.graph[5].data == 0x11,
        g.graph[6].data == 0x0d,
        g.graph[7].data == 0xaa,
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

func test1(_ g: Graph<UInt8>) -> Bool {
     if
        g.count == 10,
        g.graph[0].data == 0x64,
        g.graph[1].data == 0x65,
        g.graph[2].data == 0x61,
        g.graph[3].data == 0x64,
        g.graph[4].data == 0x62,
        g.graph[5].data == 0x11,
        g.graph[6].data == 0x0d,
        g.graph[7].data == 0xaa,
        g.graph[8].data == 0xf2,
        g.graph[9].data == 0x34,
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
        return false
     }
    return true
}

func test2(_ x: Graph<UInt8>) -> Bool {
    let comp = x.stronglyConnectedComponents()
    if
        comp.count > 2,
        comp[0].count >= 3,
        comp[1].count >= 3,
        comp[2].count >= 3
    {
        return false
    }
    return true
}

func test3(_ g: Graph<UInt8>) -> Bool {
    if g.isLargeAndCyclic() {
    
        if
            g.graph[0].data == 0x00,
            g.graph[1].data == 0x01,
            g.graph[2].data == 0x02,
            g.graph[3].data == 0x03,
            g.graph[4].data == 0x04
        {
            return false
        }
    
    }
    return true
}

try CommandLineFuzzer.launch(test: test3, generator: GraphGenerator())
