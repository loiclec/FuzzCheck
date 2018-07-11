//
//  Mock.swift
//  FuzzerTests
//

@testable import FuzzCheck

typealias MockFuzzerState = FuzzerState<Void, MockInputProperties<Void>, MockWorld<MockInputProperties<Void>>, MockSensor>
typealias MockInputPool = MockFuzzerState.InputPool

struct MockInputProperties <Input> : FuzzerInputProperties {
    static func hash(of input: Input) -> Int {
        return 1
    }
    static func complexity(of input: Input) -> Double {
        return 1.0
    }
}

final class MockFeature: FuzzerSensorFeature, Hashable, Codable {
    let score: Double
    
    /// Initialize the MockFeature with a score of 1.0
    init() {
        self.score = 1.0
    }
    
    init(score: Double) {
        self.score = score
    }

    static func == (lhs: MockFeature, rhs: MockFeature) -> Bool {
        return lhs === rhs
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

struct MockSensor: FuzzerSensor {
    typealias Feature = MockFeature
    
    init(features: AnyIterator<[MockFeature]>) {
        self.currentFeatures = features.next() ?? []
        self.nextFeatures = features
    }
    
    private let nextFeatures: AnyIterator<[MockFeature]>
    private var currentFeatures: [MockFeature]
    
    var isRecording: Bool = false
    
    mutating func resetCollectedFeatures() {
        currentFeatures = nextFeatures.next() ?? []
    }
    
    func iterateOverCollectedFeatures(_ handle: (MockFeature) -> Void) {
        currentFeatures.forEach(handle)
    }
}

struct MockWorld <P: FuzzerInputProperties>: FuzzerWorld {
    typealias Input = P.Input
    typealias Properties = P
    typealias Feature = MockFeature
    
    var _clock: UInt = 0
    var rand: FuzzerPRNG
    
    mutating func getPeakMemoryUsage() -> UInt {
        return 1
    }
    
    mutating func clock() -> UInt {
        _clock += 1
        return _clock
    }
    
    mutating func readInputCorpus() throws -> [P.Input] {
        return []
    }
    
    mutating func readInputFile() throws -> P.Input {
        fatalError()
    }
    
    mutating func saveArtifact(input: P.Input, features: [Feature]?, score: Double?, kind: ArtifactKind) throws {
        return
    }
    
    mutating func addToOutputCorpus(_ input: P.Input) throws {
        return
    }
    
    mutating func removeFromOutputCorpus(_ input: P.Input) throws {
        return
    }
    
    mutating func reportEvent(_ event: FuzzerEvent, stats: FuzzerStats) {
        return
    }
}
