
import XCTest
@testable import Fuzzer

class FuzzerTests: XCTestCase {
    
    func testWeightedPick() {
        var r = Rand.init(seed: 0)
        var weights: [UInt64] = Array.init()
        for i in 0 ..< 10 {
            weights.append(UInt64(i))
        }
        let cumulativeWeights = weights.scan(0, { $0 + $1 })
        print(weights)
        print(cumulativeWeights)
        var timesChosen = weights.map { _ in 0 }
        for _ in 0 ..< 10_000 {
            
            timesChosen[r.weightedPickIndex(cumulativeWeights: cumulativeWeights)] += 1
        }
       print(timesChosen)
    }
    
    func testRandom() {
        var r = Rand.init(seed: 2)
        var timesChosen = Array.init(repeating: 0, count: 128)
        for _ in 0 ..< 10_000 {
            let x = r.next()
            for i in 0 ..< 32 {
                let j = (x >> (i &* 2)) & 0b11
                timesChosen[(i*4) + Int(j)] += 1
            }
        }
        print(timesChosen)
    }
}
