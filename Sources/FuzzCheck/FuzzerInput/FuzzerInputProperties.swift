
/// A protocol giving some information about values of type Input, such as its complexity or hash.
public protocol FuzzerInputProperties {
    associatedtype Input
    
    /// A type isomorphic to Input that is Codable. This exists here so
    /// that non-nominal types can be FuzzerInputGenerator too
    associatedtype CodableInput: Codable = Input
    
    /**
     Returns the complexity of the given input.
     
     FuzzCheck will prefer using inputs with a smaller complexity.
     
     - Important: The return value must be >= 0.0
     
     ## Examples
     - an array might have a complexity equal to the sum of complexities of its elements
     - an integer might have a complexity equal to the number of bytes used to represent it
     */
    static func complexity(of input: Input) -> Double
    
    static func hash(_ input: Input, into hasher: inout Hasher)
    
    static func convertToCodable(_ input: Input) -> CodableInput
    static func convertFromCodable(_ codable: CodableInput) -> Input
}

extension FuzzerInputProperties {
    internal static func adjustedComplexity(of input: Input) -> Double {
        let cplx = complexity(of: input)
        precondition(cplx >= 0.0)
        return cplx + 1.0
    }
}

extension FuzzerInputProperties {
    public static func hashValue(of input: Input) -> Int {
        var h = Hasher()
        hash(input, into: &h)
        return h.finalize()
    }
}

extension FuzzerInputProperties where Input: Hashable {
    public static func hash(_ input: Input, into hasher: inout Hasher) {
        input.hash(into: &hasher)
    }
}

extension FuzzerInputProperties where Input == CodableInput {
    public static func convertToCodable(_ input: Input) -> CodableInput {
        return input
    }
    public static func convertFromCodable(_ codable: CodableInput) -> Input {
        return codable
    }
}
