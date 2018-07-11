//
//  InputPoolTests.swift
//  FuzzerTests
//

import XCTest
@testable import FuzzCheck


let f: [MockFeature] = {
    var f: [MockFeature] = []
    for _ in 0 ..< 10 {
        f.append(MockFeature())
    }
    return f
}()

let u1 = MockInputPool.Element(
    input: (),
    complexity: 10.0,
    features: [f[0], f[1], f[2], f[3]]
)
let u2 = MockInputPool.Element(
    input: (),
    complexity: 5.0,
    features: [f[4]]
)
let u3 = MockInputPool.Element(
    input: (),
    complexity: 5.0,
    features: [f[5]]
)
let u4 = MockInputPool.Element(
    input: (),
    complexity: 2.0,
    features: [f[6], f[7]]
)
let u5 = MockInputPool.Element(
    input: (),
    complexity: 1.0,
    features: [f[6]]
)

class InputPoolTests: XCTestCase {
    
    func testCoverageScore() {
        let pool = MockInputPool()
        _ = pool.add(u1)
        _ = pool.add(u2)
        _ = pool.add(u3)
        _ = pool.add(u4)
        _ = pool.add(u5)
        
        XCTAssertEqual(pool.inputs.count, 5)
        
        XCTAssertGreaterThan(pool.inputs[0].coverageScore, pool.inputs[1].coverageScore)
        XCTAssertGreaterThan(pool.inputs[0].coverageScore, pool.inputs[2].coverageScore)
        XCTAssertGreaterThan(pool.inputs[0].coverageScore, pool.inputs[3].coverageScore)
        XCTAssertGreaterThan(pool.inputs[0].coverageScore, pool.inputs[4].coverageScore)
        
        XCTAssertEqual(pool.inputs[1].coverageScore, pool.inputs[2].coverageScore)
        
        XCTAssertEqual(pool.inputs[3].coverageScore, f[6].score / 5 + f[7].score)
        XCTAssertEqual(pool.inputs[4].coverageScore, f[6].score * 4 / 5)
    }
}
