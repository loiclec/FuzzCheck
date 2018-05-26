
import XCTest
@testable import Fuzzer

class FuzzerTests: XCTestCase {
    
    func testWeightedPick() {
        var r = Rand.init(seed: 0)
        var weights: [(UInt8, UInt64)] = Array.init()
        for i in 0 ..< 1_000 {
            weights.append((0, UInt64(i * 5)))
        }
        
        measure {
            var timesChosen = weights.map { _ in 0 }
            for i in 0 ..< 100000 {
                timesChosen[r.weightedPickIndex(from: weights)] += 1
            }
           print(timesChosen[2])
        }
    }
    
}
