
/// A protocol giving some information about values of type Input, such as its complexity or hash.
public protocol FuzzerInputProperties {
    associatedtype Input
    /**
     Returns the complexity of the given input.
     
     FuzzCheck will prefer using inputs with a smaller complexity.
     
     - Important: The return value must be >= 0
     
     ## Examples
     - an array might have a complexity equal to the sum of complexities of its elements
     - an integer might have a complexity equal to the number of bytes used to represent it
     */
    static func complexity(of input: Input) -> Double
    
    /// - Returns: the hash value of the given input
    static func hash(of input: Input) -> Int
}
