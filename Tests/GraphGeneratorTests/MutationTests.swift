//
//  GraphGeneratorTests.swift
//  FuzzerTests
//
//  Created by Loïc Lecrenier on 30/06/2018.
//

import XCTest
import Fuzzer
import ModuleToTest
@testable import ModuleToTestMutators

class MutationTests: XCTestCase {
    func testMut1() {
        let gen = GraphGenerator.init()
        var g = Graph<UInt8>.init()
        _ = g.addVertex(0)
        _ = g.addVertex(1)
        _ = g.addVertex(2)
        _ = g.addVertex(3)
        var r = Rand(seed: 0)
        print(g.dotDescription())
        for i in 0 ..< 1000 {
            print("iter:", i)
            print("size:", g.totalSize)
            print()
            _ = gen.mutators.mutate(&g, &r)
        }
        print(g.dotDescription())
    }
}
