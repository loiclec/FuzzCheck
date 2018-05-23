
public protocol FuzzInput {
    func complexity() -> Int
    func hash() -> Int
}

public protocol FuzzTarget {
    associatedtype Input: FuzzInput
    
    func newInput(_ r: inout Rand) -> Input
    
    func run(_ i: Input) -> Int
}

public typealias Mutator<Mutated> = (inout Mutated, inout Rand) -> Bool

public protocol Mutators {
    associatedtype Mutated: FuzzInput
    
    func weightedMutators(for x: Mutated) -> [(Mutator<Mutated>, UInt64)]
}
extension Mutators {
    func mutate(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        for mutator in r.weightedPicks(from: weightedMutators(for: x)) {
            if mutator(&x, &r) { return true }
        }
        return false
    }
}

extension Int: FuzzInput {
    public init(_ rand: inout Rand) {
        self = rand.int()
    }
    
    public func complexity() -> Int {
        return 1
    }
    
    public func hash() -> Int {
        return self.hashValue
    }
}

struct IntMutators: Mutators {
    typealias Mutated = Int
    
    func nudge(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        let add = r.int(inside: -10 ..< 10)
        x = x &+ r.int(inside: -10 ..< 10)
        return add != 0
    }
    
    func random(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        x = r.int()
        return true
    }
    
    func special(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        let oldX = x
        x = r.pick(0, Int.min, Int.max)
        return x != oldX
    }
    
    func weightedMutators(for x: Mutated) -> [((inout Mutated, inout Rand) -> Bool, UInt64)] {
        return [
            (self.special, 10),
            (self.random, 10),
            (self.nudge, 10),
        ]
    }
}

extension Array: FuzzInput where Element: FuzzInput {
    public func complexity() -> Int {
        return reduce(1) { $0 + $1.complexity() }
    }
    
    public func hash() -> Int {
        return self.reduce(1.hashValue) { ($0 &* 65371) ^ $1.hash() }
    }
}

struct ArrayMutators <M: Mutators> : Mutators {
    typealias Mutated = Array<M.Mutated>
    
    let initializeElement: (inout Rand) -> M.Mutated
    let elementMutators: M
    
    func appendNew(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        x.append(initializeElement(&r))
        return true
    }
    
    func appendRecycled(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let y = r.pick(from: x)
        x.append(y)
        return true
    }
    
    func appendRepeatedNew(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        let y = initializeElement(&r)
        let count = r.positiveInt(x.count) + 1 // TODO: don't use uniform distribution, favor lower values
        x += repeatElement(y, count: count)
        return true
    }
    
    func insertNew(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        let i = r.int(inside: x.indices)
        x.insert(initializeElement(&r), at: i)
        return true
    }
    
    func insertRecycled(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let y = r.pick(from: x)
        let i = r.int(inside: x.indices)
        x.insert(y, at: i)
        return true
    }
    
    func insertRepeatedNew(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        let y = initializeElement(&r)
        let count = r.positiveInt(x.count) + 1 // TODO: don't use uniform distribution, favor lower values
        let i = r.int(inside: x.indices)
        x.insert(contentsOf: repeatElement(y, count: count), at: i)
        return true
    }
    
    func removeLast(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        x.removeLast()
        return true
    }
    
    func removeFirst(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        x.removeFirst()
        return true
    }
    
    func removeNFirst(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        let count = r.positiveInt(x.count) + 1  // TODO: don't use uniform distribution, favor lower values
        x.removeFirst(count)
        return true
    }
    
    func removeRandom(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        x.remove(at: r.positiveInt(x.endIndex))
        return true
    }
    
    func swap(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        let (i, j) = (r.int(inside: x.indices), r.int(inside: x.indices))
        x.swapAt(i, j)
        return i != j
    }
    
    func removeSubrange(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        let start = r.int(inside: x.indices)
        let end = r.int(inside: start ..< x.endIndex)
        x.removeSubrange(start ..< end)
        return start != end
    }
    
    func moveSubrange(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        let sourceStart = r.int(inside: x.indices)
        let sourceEnd = r.int(inside: sourceStart ..< x.endIndex)
        
        let destStart = r.int(inside: x.indices)
        let destEnd = destStart + sourceStart.distance(to: sourceEnd)
        x.replaceSubrange(destStart ..< destEnd, with: x[sourceStart ..< sourceEnd])
        
        return sourceStart != sourceEnd && sourceStart != destStart
    }
    
    func mutateElement(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        let i = r.int(inside: x.indices)
        return elementMutators.mutate(&x[i], &r)
    }
    
    func mutateSubrange(_ x: inout Array<M.Mutated>, _ r: inout Rand) -> Bool {
        let start = r.int(inside: x.indices)
        let end = r.int(inside: start ..< x.endIndex) // TODO: do no use uniform distribution
        var res = false
        for i in start ..< end {
            res = res || elementMutators.mutate(&x[i], &r)
        }
        return res
    }
    
    func replaceCompletely(_ x: inout Array<M.Mutated>, _ r: inout Rand) -> Bool {
        x.removeAll()
        let count = r.positiveInt(256)
        for _ in 0 ..< count {
            x.append(initializeElement(&r))
        }
        return true
    }
    
    func weightedMutators(for x: Mutated) -> [(Mutator<Mutated>, UInt64)] {
        
        let haveRepeatingVariant: [(Mutator<Mutated>, UInt64)] = [
            (self.appendNew, 40),
            (self.appendRecycled, 40),
            (self.insertNew, 40),
            (self.insertRecycled, 40),
            (self.mutateElement, 20 + UInt64(x.count / 4)),
            (self.swap, 20 + UInt64(x.count / 4)),
            (self.removeLast, 40),
            (self.removeRandom, 40)
        ]
        let repeatingVariants = haveRepeatingVariant.map { (m: (Mutator<Mutated>, UInt64)) -> (Mutator<Mutated>, UInt64) in
            let rm = ArrayMutators.repeatMutator(m.0, count: { (r: inout Rand, max: Int) -> Int in
                return r.positiveInt(max)
            })
            return (rm, m.1 / 4)
        }
        let others: [(Mutator<Mutated>, UInt64)] = [
            (self.appendRepeatedNew, 10),
            (self.insertRepeatedNew, 10),
            (self.moveSubrange, 10),
            (self.removeSubrange, 10),
            (self.removeFirst, 10),
            (self.removeNFirst, 10),
            (self.mutateSubrange, 10),
            (self.replaceCompletely, 1)
        ]
        
        return haveRepeatingVariant + repeatingVariants + others
    }
    
    static func repeatMutator(_ m: @escaping (inout Mutated, inout Rand) -> Bool, count: @escaping (inout Rand, Int) -> Int) -> (inout Mutated, inout Rand) -> Bool {
        return { (x: inout Mutated, r: inout Rand) -> Bool in
            var res = false
            for _ in 0 ..< count(&r, x.count) { // don't use uniform distribution, favor lower values
                let res2 = m(&x, &r)
                res = res || res2
            }
            return res
        }
    }
}



