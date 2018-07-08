//
//  Mock.swift
//  FuzzerTests
//

@testable import FuzzCheck

typealias MockFuzzerState = FuzzerState<Void, MockUnitProperties<Void>, MockWorld<MockUnitProperties<Void>>>
typealias MockUnitPool = MockFuzzerState.UnitPool

struct MockUnitProperties <Unit> : FuzzUnitProperties {
    static func hash(of unit: Unit) -> Int {
        return 1
    }
    static func complexity(of unit: Unit) -> Double {
        return 1.0
    }
}

struct MockWorld <P: FuzzUnitProperties>: FuzzerWorld {
    typealias Unit = P.Unit
    typealias Properties = P
    
    var _clock: UInt = 0
    var rand: Rand
    
    mutating func getPeakMemoryUsage() -> UInt {
        return 1
    }
    
    mutating func clock() -> UInt {
        _clock += 1
        return _clock
    }
    
    mutating func readInputCorpus() throws -> [P.Unit] {
        return []
    }
    
    mutating func readInputFile() throws -> P.Unit {
        fatalError()
    }
    
    mutating func saveArtifact(unit: P.Unit, features: [Feature]?, coverage: Double?, kind: ArtifactKind) throws {
        return
    }
    
    mutating func addToOutputCorpus(_ unit: P.Unit) throws {
        return
    }
    
    mutating func removeFromOutputCorpus(_ unit: P.Unit) throws {
        return
    }
    
    mutating func reportEvent(_ event: FuzzerEvent, stats: FuzzerStats) {
        return
    }
    
    mutating func readInputCorpusWithFeatures() throws -> [(P.Unit, [Feature])] {
        return  []
    }
}
