//
//  InputPoolTests.swift
//  FuzzerTests
//

import XCTest
@testable import FuzzCheck

/// A list of 100 unique features, each with a score of 1.0
let f: [MockFeature] = {
    var f: [MockFeature] = []
    for _ in 0 ..< 100 {
        f.append(MockFeature())
    }
    return f
}()

class InputPoolTests: XCTestCase {
    
    func testCoverageScore0() {
        let u1 = MockInputPool.Element(
            input: (),
            complexity: 10.0,
            features: [f[0], f[1], f[2]]
        )
        let u2 = MockInputPool.Element(
            input: (),
            complexity: 5.0,
            features: [f[1], f[2]]
        )
        let u3 = MockInputPool.Element(
            input: (),
            complexity: 5.0,
            features: [f[1], f[3]]
        )

        let pool = MockInputPool()
        _ = pool.add(u1)
        _ = pool.add(u2)
        _ = pool.add(u3)
        
        print(pool.inputs.map { $0.score })
    }
    
    func testCoverageScore() {
        
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
        
        let pool = MockInputPool()
        _ = pool.add(u1)
        _ = pool.add(u2)
        _ = pool.add(u3)
        _ = pool.add(u4)
        _ = pool.add(u5)
        
        XCTAssertEqual(pool.inputs.count, 5)
        
        XCTAssertGreaterThan(pool.inputs[0].score, pool.inputs[1].score)
        XCTAssertGreaterThan(pool.inputs[0].score, pool.inputs[2].score)
        XCTAssertGreaterThan(pool.inputs[0].score, pool.inputs[3].score)
        XCTAssertGreaterThan(pool.inputs[0].score, pool.inputs[4].score)
        
        XCTAssertEqual(pool.inputs[1].score, pool.inputs[2].score)
        
        XCTAssertEqual(pool.inputs[3].score, f[6].score / 5 + f[7].score)
        XCTAssertEqual(pool.inputs[4].score, f[6].score * 4 / 5)
    }
}
