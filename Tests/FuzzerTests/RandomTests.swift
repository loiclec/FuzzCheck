
import XCTest
@testable import Fuzzer

class FuzzerTests: XCTestCase {
    
    func testWeightedPick() {
        var r = Rand.init(seed: 0)
        var weights: [UInt64] = Array.init()
        for i in 0 ..< 10 {
            weights.append(UInt64(i))
        }
        //let cumulativeWeights = weights.scan(0, { $0 + $1 })
        //print(weights)
        //print(cumulativeWeights)
        /*
        measure {
            var timesChosen = weights.map { _ in 0 }
            for _ in 0 ..< 10_000 {
                
                timesChosen[r.weightedPickIndex(cumulativeWeights: cumulativeWeights)] += 1
            }
           print(timesChosen)
        }*/
    }
    
    func testIncludes() {
        let a = [1, 2, 3, 4, 8, 9]
        let b = [1, 2]
        let c = [2, 3]
        let d = [3, 4]
        let e = [1, 3]
        let f = [2, 4]
        let g = [1]
        let h = [4]
        let i = [1, 2, 3, 4, 8, 9]
        let j = [1, 2, 3, 4, 8, 9, 10]
        let k = [0, 1, 2, 3, 9]
        let l = [1, 4, 5, 10]
        let m: [Int] = []
    
        for x in [b, c, d, e, f, g, h, i, j, k, l, m] {
            print(a.includes(x))
        }
    }
    
}
