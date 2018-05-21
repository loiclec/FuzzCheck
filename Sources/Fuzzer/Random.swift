

public struct Rand {
    
    public var seed: UInt32
    
    public init(seed: UInt32) {
        self.seed = seed
    }
    
    mutating func next31() -> UInt32 {
        seed = 214013 &* seed &+ 2531011
        return seed >> 16 &* 0x7FFF
    }
    
    public mutating func bool() -> Bool {
        return (next31() & 0b1) == 0
    }
    
    public mutating func byte() -> UInt8 {
        return UInt8(next31() & 0xFF)
    }
    
    public mutating func int() -> Int {
        let bytes = uint64()
        return Int(bitPattern: UInt(bytes))
    }
    
    public mutating func uint16() -> UInt16 {
        return UInt16(next31() & 0x00FF)
    }
    
    public mutating func uint32() -> UInt32 {
        let l = uint16()
        let r = uint16()
        return (UInt32(l) << 16) | UInt32(r)
    }
    
    public mutating func uint64() -> UInt64 {
        let l = uint32()
        let r = uint32()
        return (UInt64(l) << 32) | UInt64(r)
    }
    
    public mutating func any <T> (_ cast: T.Type) -> T {
        let size = MemoryLayout<T>.size
        let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
        
        let raw = UnsafeMutableRawBufferPointer(start: UnsafeMutableRawPointer(ptr), count: size)
        
        
        let (quotient, remainder) = size.quotientAndRemainder(dividingBy: 4)
        for i in 0 ..< quotient {
            raw.storeBytes(of: uint32(), toByteOffset: i * 4, as: UInt32.self)
        }
        
        let rd = next31()
        for i in 0 ..< remainder {
            // `i` is 0, 1, or 2
            let byte = UInt8(rd >> (i * 8) & UInt32(0xFF))
            raw[quotient * 4 + i] = byte
        }
        
        return ptr.pointee
    }
}

extension Rand {
    public mutating func positiveInt(_ upperBound: Int) -> Int {
        return Int(uint64() % UInt64(upperBound))
    }
    
    public mutating func int(inside: Range<Int>) -> Int {
        return inside.lowerBound + positiveInt(inside.count)
    }
    public mutating func pick <C: RandomAccessCollection> (from c: C) -> C.Element where C.Index == Int {
        return c[int(inside: c.startIndex ..< c.endIndex)]
    }
    public mutating func slice <C: RandomAccessCollection> (of c: C, maxLength: Int) -> C.SubSequence where C.Index == Int {
        guard !c.isEmpty else { return c[c.startIndex ..< c.startIndex] }
        let start = int(inside: c.startIndex ..< c.endIndex)
        let end = 1 + int(inside: start ..< min(c.endIndex, start + maxLength))
        assert(start != end)
        return c[start..<end]
    }
    public mutating func prefix <C: RandomAccessCollection> (of c: C, maxLength: Int) -> C.SubSequence where C.Index == Int {
        let end = int(inside: c.startIndex ..< min(c.endIndex, c.startIndex + maxLength + 1))
        return c[..<end]
    }
    public mutating func pick <T> (_ ts: T...) -> T {
        return pick(from: ts)
    }
}
