
var array: [Int] = []

var rand = Rand.init(seed: 1)

public func analyze <F: FuzzTarget> (_ f: F) {
    for _ in 0 ..< 2 {
    	print("will run")
        f.run(F.Input(&rand))
    }
    print(TPC.getTotalPCCoverage())
    print(TPC.numInline8bitCounters)
    print(Array(eightBitCounters[0 ..< 100]))
    print(Array(PCs[0 ..< 100]))
}
