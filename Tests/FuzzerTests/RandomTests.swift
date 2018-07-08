
import XCTest
@testable import FuzzCheck

class FuzzerTests: XCTestCase {
    func testWeightedPick() {
        var r = Rand.init(seed: 0)
        var weights: [UInt64] = Array.init()
        for i in 0 ..< 10 {
            weights.append(UInt64(i))
        }
        let cumulativeWeights = [1, 6, 7, 10, 11, 12, 13, 14, 17, 18, 19, 20].enumerated().map { ($0.0, $0.1) }
        // print(weights)
        print(cumulativeWeights.map { $0.1 })
        var timesChosen = cumulativeWeights.map { _ in 0 }
        for _ in 0 ..< 100_000 {
            
            timesChosen[r.weightedRandomElement(from: cumulativeWeights, minimum: 0)] += 1
        }
       print(timesChosen)
    }
    
    func testRandom() {
        var r = Rand(seed: 2)
        var timesChosen = Array.init(repeating: 0, count: 128)
        for _ in 0 ..< 1_000_000 {
            let i = Int.random(in: 0 ..< timesChosen.count, using: &r)// timesChosen.indices.randomElement(using: &r)!
            timesChosen[i] += 1
        }
        print(timesChosen)
    }
    
    func testBoolWithOdds() {
        var r = Rand.init(seed: 2)
        var timesTrue = 0
        for _ in 0 ..< 1_000_000 {
            if r.bool(odds: 0.27) {
                timesTrue += 1
            }
        }
        print(timesTrue)
    }
}
