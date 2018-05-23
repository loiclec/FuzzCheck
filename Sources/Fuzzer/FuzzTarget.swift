
public protocol FuzzInput {
    init(_ rand: inout Rand)
    
    func complexity() -> Int
    func hash() -> DoubleWidthInt
}

public protocol FuzzTarget {
    associatedtype Input: FuzzInput
    
    func run(_ i: Input) -> Int
}

