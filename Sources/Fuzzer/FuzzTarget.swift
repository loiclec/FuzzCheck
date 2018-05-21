
public protocol FuzzInput {
    init(_ rand: inout Rand)
}

public protocol FuzzTarget {
    associatedtype Input: FuzzInput
    
    func run(_ i: Input)
}

