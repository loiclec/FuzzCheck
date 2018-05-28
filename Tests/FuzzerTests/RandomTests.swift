
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
        
        measure {
            var timesChosen = weights.map { _ in 0 }
            for _ in 0 ..< 10_000 {
                
                timesChosen[r.weightedPickIndex(cumulativeWeights: cumulativeWeights)] += 1
            }
           print(timesChosen)
        }
    }
    
}
