
public func bar(_ i: Int) -> Int {
    if i % 5 == 0  {
        return i % 3
    } else if i % 7 == 0 {
        return i + 4
    } else if i % 9 == 0 {
        return i - 1
    } else {
        return i
    }
}
