
public struct IntegerFuzzerInputMutators <T: FixedWidthInteger & RandomInitializable> : FuzzerInputMutatorGroup {
    public typealias Input = T
    
    public enum Mutator {
        case nudge
        case random
        case special
    }
    
    let maxNudge: UInt
    let specialValues: [T]
    
    public func mutate(_ input: inout Input, with mutator: Mutator, _ rand: inout FuzzerPRNG) -> Bool {
        switch mutator {
        case .nudge:
            return nudge(&input, &rand)
        case .random:
            return random(&input, &rand)
        case .special:
            return special(&input, &rand)
        }
    }
    
    func nudge(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
        let nudge = Input(r.next(upperBound: maxNudge))
        let op: (Input, Input) -> Input = Bool.random(using: &r) ? (&-) : (&+)
        x = op(x, nudge)
        return true
    }
    
    func random(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
        x = T.random(using: &r)
        return true
    }
    
    func special(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
        let oldX = x
        x = specialValues.randomElement() ?? x
        return x != oldX
    }
    
    public init(specialValues: [T]) {
        self.maxNudge = 10
        self.specialValues = specialValues
    }
    
    public let weightedMutators: [(Mutator, UInt)] = [
        (.special, 1),
        (.random, 11),
        (.nudge, 21),
    ]
}

public struct IntegerFuzzerGenerator <T: FixedWidthInteger & RandomInitializable & Codable> : FuzzerInputGenerator {
    
    public let baseInput = 0 as T
    let mutators: IntegerFuzzerInputMutators<T>
    
    public init(specialValues: [T]) {
        self.mutators = IntegerFuzzerInputMutators(specialValues: specialValues)
    }
    
    public func newInput(maxComplexity: Double, _ rand: inout FuzzerPRNG) -> T {
        return T.random(using: &rand)
    }
    
    public func mutate(_ x: inout T, _ r: inout FuzzerPRNG) -> Bool {
        return mutators.mutate(&x, &r)
    }

    public static func complexity(of: T) -> Double {
        return Double(T.bitWidth) / 8
    }
}


extension FixedWidthInteger where Self: UnsignedInteger {
    /**
     Return an array of “special” values of this UnsignedInteger type that
     deserve to be prioritized during fuzzing.
     
     For example: 0, Int8.max, Self.max, etc.
    */
    fileprivate static func specialValues() -> [Self] {
        var result: [Self] = []
        result.append(0)
        var i = 8
        while i <= bitWidth {
            defer { i *= 2 }
            let ones = max
            let zeros = min
            
            let umax = zeros | (ones >> (bitWidth - i))
            let umax_lesser = umax / 2
            
            result.append(umax)
            result.append(umax_lesser)
        }
        return result
    }
}

extension FixedWidthInteger where Self: SignedInteger {
    /**
     Return an array of “special” values of this UnsignedInteger type that
     deserve to be prioritized during fuzzing.
     
     For example: 0, -1, Int8.min, Int8.max, Int16.min, Self.max, etc.
    */
    fileprivate static func specialValues <U: FixedWidthInteger & UnsignedInteger> (_ initWithBitPattern: (U) -> Self) -> [Self] {
        var result: [Self] = []
        result += [0, -1]
        var i = 8
        while i < bitWidth {
            defer { i *= 2 }
            let ones = U.max
            let zeros = U.min
            
            let umax = zeros | (ones >> (bitWidth - i))
            let umin = zeros | (ones << i)
            
            let max = initWithBitPattern(umax)
            let lesser_max = max / 2
            let min = initWithBitPattern(umin)
            let lesser_min = min / 2
            
            result += [max, lesser_max, min, lesser_min]
        }
        result += [max, min]
        return result
    }
}

extension IntegerFuzzerGenerator where T: UnsignedInteger {
    public init() {
        self.init(specialValues: T.specialValues())
    }
}

extension IntegerFuzzerGenerator where T == Int8 {
    public init() {
        self.init(specialValues: T.specialValues(T.init(bitPattern:)))
    }
}

extension IntegerFuzzerGenerator where T == Int16 {
    public init() {
        self.init(specialValues: T.specialValues(T.init(bitPattern:)))
    }
}

extension IntegerFuzzerGenerator where T == Int32 {
    public init() {
        self.init(specialValues: T.specialValues(T.init(bitPattern:)))
    }
}

extension IntegerFuzzerGenerator where T == Int64 {
    public init() {
        self.init(specialValues: T.specialValues(T.init(bitPattern:)))
    }
}

extension IntegerFuzzerGenerator where T == Int {
    public init() {
        self.init(specialValues: T.specialValues(T.init(bitPattern:)))
    }
}
