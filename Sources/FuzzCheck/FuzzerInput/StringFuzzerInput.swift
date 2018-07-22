//
//  StringFuzzerInput.swift
//  FuzzCheck
//

public struct UnicodeScalarViewFuzzerInput: FuzzerInputGenerator, FuzzerInputProperties {
    public typealias Input = String
    
    public let baseInput: String = ""
    let mutators = UnicodeScalarViewFuzzerMutators()
    
    public func newInput(maxComplexity: Double, _ rand: inout FuzzerPRNG) -> String {
        let targetComplexity = Double.random(in: 1 ..< maxComplexity, using: &rand)
        
        var s = ""
        while true {
            _ = mutate(&s, &rand)
            if UnicodeScalarViewFuzzerInput.complexity(of: s) >= targetComplexity {
                _ = mutators.mutate(&s, with: .removeRandom, &rand)
                return s
            }
        }
    }
    
    public func mutate(_ input: inout String, _ rand: inout FuzzerPRNG) -> Bool {
        return mutators.mutate(&input, &rand)
    }
    public static func complexity(of input: String) -> Double {
        return Double(input.utf16.count)
    }
}

struct UnicodeScalarViewFuzzerMutators: FuzzerInputMutatorGroup {
    public typealias Input = String
        
    enum Mutator {
        case appendRandom
        case insert
        case mutateElement
        case removeLast
        case removeRandom
    }
    
    func randomScalar(_ rand: inout FuzzerPRNG) -> UnicodeScalar {
        switch UInt8.random(in: 0...10, using: &rand) {
        // basic ascii code points
        case 0...4:
            return UnicodeScalar(UInt8.random(in: 0x20 ..< 0x7E, using: &rand))
        // common newlines/whitespace
        case 5:
            let code: UInt16 = [
                0x09, 0x10, 0x0B, 0x0D, 0xA0
            ].randomElement(using: &rand)!
            return UnicodeScalar(code)!
        // any 8-bit codepoint
        case 6:
            return UnicodeScalar(UInt8.random(using: &rand))
        // any 16-bit codepoint
        case 7:
            return UnicodeScalar(UInt16.random(using: &rand)) ?? UnicodeScalar(UInt8.random(using: &rand))
        // general punctuation
        case 8:
            let range: ClosedRange<UInt16> = 0x2000...0x206F
            return UnicodeScalar(UInt16.random(in: range, using: &rand))!
        // emoji, country codes, other less interesting things
        case 9:
            let range: ClosedRange<UInt32> = 0x1F100...0x1F9FF
            return UnicodeScalar(UInt32.random(in: range, using: &rand))!
        // any scalar
        case 10:
            while true {
                let code = UInt32.random(in: 0 ... 0x10FFFF, using: &rand)
                if let scalar = UnicodeScalar(code) {
                    return scalar
                }
            }
        default:
            fatalError()
        }
    }
    
    func mutate(_ input: inout String, with mutator: Mutator, _ rand: inout FuzzerPRNG) -> Bool {
        switch mutator {
        case .appendRandom:
            input.unicodeScalars.append(randomScalar(&rand))
            return true
        case .insert:
            guard let idx = input.unicodeScalars.indices.randomElement(using: &rand) else {
                return false
            }
            input.unicodeScalars.insert(randomScalar(&rand), at: idx)
            return true
            
        case .mutateElement:
            guard let idx = input.unicodeScalars.indices.randomElement(using: &rand) else {
                return false
            }
            input.unicodeScalars.replaceSubrange(idx ..< input.unicodeScalars.index(after: idx), with: CollectionOfOne(randomScalar(&rand)))
            return true
            
        case .removeLast:
            guard !input.isEmpty else { return false }
            input.unicodeScalars.removeLast()
            return true
            
        case .removeRandom:
            guard let idx = input.unicodeScalars.indices.randomElement(using: &rand) else {
                return false
            }
            input.unicodeScalars.remove(at: idx)
            return true
        }
    }
    
    public var weightedMutators: [(Mutator, UInt)] = [
        (.appendRandom, 1),
        (.insert, 2),
        (.mutateElement, 3),
        (.removeLast, 4),
        (.removeRandom, 5),
    ]
}


