//
//  UnitPoolTests.swift
//  FuzzerTests
//

import XCTest
@testable import FuzzCheck


let f1 = Feature.edge(.init(pcguard: 0, counter: 1))
let f2 = Feature.edge(.init(pcguard: 1, counter: 1))
let f3 = Feature.edge(.init(pcguard: 2, counter: 1))
let f4 = Feature.edge(.init(pcguard: 3, counter: 1))
let f5 = Feature.edge(.init(pcguard: 4, counter: 1))
let f6 = Feature.edge(.init(pcguard: 5, counter: 1))
let f7 = Feature.edge(.init(pcguard: 6, counter: 1))
let f8 = Feature.edge(.init(pcguard: 7, counter: 1))

let u1 = MockUnitPool.UnitInfo(
    unit: (),
    complexity: 10.0,
    features: [f1, f2, f3, f4]
)
let u2 = MockUnitPool.UnitInfo(
    unit: (),
    complexity: 5.0,
    features: [f5]
)
let u3 = MockUnitPool.UnitInfo(
    unit: (),
    complexity: 5.0,
    features: [f6]
)
let u4 = MockUnitPool.UnitInfo(
    unit: (),
    complexity: 2.0,
    features: [f7, f8]
)
let u5 = MockUnitPool.UnitInfo(
    unit: (),
    complexity: 1.0,
    features: [f7]
)

class UnitPoolTests: XCTestCase {
    
    func testCoverageScore() {
        let pool = MockUnitPool()
        _ = pool.add(u1)
        _ = pool.add(u2)
        _ = pool.add(u3)
        _ = pool.add(u4)
        _ = pool.add(u5)
        
        XCTAssertEqual(pool.units.count, 5)
        
        XCTAssertGreaterThan(pool.units[0].coverageScore, pool.units[1].coverageScore)
        XCTAssertGreaterThan(pool.units[0].coverageScore, pool.units[2].coverageScore)
        XCTAssertGreaterThan(pool.units[0].coverageScore, pool.units[3].coverageScore)
        XCTAssertGreaterThan(pool.units[0].coverageScore, pool.units[4].coverageScore)
        
        XCTAssertEqual(pool.units[1].coverageScore, pool.units[2].coverageScore)
        
        XCTAssertEqual(pool.units[3].coverageScore, f7.score / 5 + f8.score)
        XCTAssertEqual(pool.units[4].coverageScore, f7.score * 4 / 5)
    }
}
