
import CBuiltinsNotAvailableInSwift
import Darwin
import Foundation

extension UnsafeMutableBufferPointer {
    static func allocateAndInitializeTo(_ x: Element, capacity: Int) -> UnsafeMutableBufferPointer {
        let b = UnsafeMutableBufferPointer.allocate(capacity: capacity)
        b.initialize(repeating: x)
        return b
    }
}

var PCs = UnsafeMutableBufferPointer<UInt>.allocateAndInitializeTo(0, capacity: TracePC.numPCs().rounded(upToMultipleOf: 8))
var eightBitCounters = UnsafeMutableBufferPointer<UInt8>.allocateAndInitializeTo(0, capacity: TracePC.numPCs().rounded(upToMultipleOf: 8) )
var PCsToGuard: [UInt: UInt32] = [:]
var PCsToStack: [UInt: [String]] = [:]

func counterToFeature <T: BinaryInteger> (_ counter: T) -> UInt32 {
    precondition(counter > 0)
   
    if counter >= 128 { return 7 }
    if counter >= 32  { return 6 }
    if counter >= 16  { return 5 }
    if counter >= 8   { return 4 }
    if counter >= 4   { return 3 }
    if counter >= 3   { return 2 }
    if counter >= 2   { return 1 }
    return 0
}

typealias PC = UInt

enum TracePC {
    // How many bits of PC are used from __sanitizer_cov_trace_pc
    static let maxNumPCs: Int = 1 << 21
    static var numGuards: Int = 0
    static var crashed = false
    
    private static var indirectFeatures: [Feature.Indirect] = []
    private static var valueProfileFeatures: [Feature.ValueProfile] = []
    private static var gepFeatures: [Feature.GEP] = []
    
    static func numPCs() -> Int {
        precondition(numGuards > 0 && numGuards < TracePC.maxNumPCs)
        return numGuards+1
    }

    static func handleInit(start: UnsafeMutablePointer<UInt32>, stop: UnsafeMutablePointer<UInt32>) {
        guard start != stop && start.pointee == 0 else { return }
        
        let buffer = UnsafeMutableBufferPointer(start: start, count: stop - start)
        for i in buffer.indices {
            numGuards += 1
            precondition(numGuards < TracePC.maxNumPCs)
            buffer[i] = UInt32(numGuards)
        }
    }

    
    static func handleCallerCallee(caller: NormalizedPC, callee: NormalizedPC) {
        let (caller, callee) = (caller.value, callee.value)
        indirectFeatures.append(.init(caller: caller, callee: callee))
    }
    
    static func getTotalPCCoverage() -> Int {
        return PCs.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
    }
    
    static func collectFeatures(debug: Bool, _ handle: (Feature) -> Void) {
        
        // the features are passed here in a deterministic order. ref: #mxrvFXBpY9ij
        let N = numPCs()
        for i in 0 ..< N where eightBitCounters[i] != 0 {
            let f = Feature.Edge(pcguard: UInt(i), intensity: eightBitCounters[i])
            //print(f)
            handle(.edge(f))
        }
        //print("---")
        
        indirectFeatures.sort()
        indirectFeatures.removeDuplicateAdjacentElements()
        
        valueProfileFeatures.sort()
        valueProfileFeatures.removeDuplicateAdjacentElements()
        
        gepFeatures.sort()
        gepFeatures.removeDuplicateAdjacentElements()

        for f in indirectFeatures {
            handle(.indirect(f))
        }
        for f in valueProfileFeatures {
            handle(.valueProfile(f))
        }
        for f in gepFeatures {
            handle(.gep(f))
        }
    }
    
    static func handleCmp <T: BinaryInteger & UnsignedInteger> (pc: NormalizedPC, arg1: T, arg2: T) {
        let pcv = pc.value
        if [18446744073708999083, 18446744073709019084, 18446744073709019190, 18446744073709019484, 18446744073709026094, 18446744073709026186, 18446744073709026289, 18446744073709026365, 18446744073709026508].contains(pcv) {
            Foundation.Thread.callStackSymbols.forEach { print($0) }
            print(String(pc.raw, radix: 16, uppercase: false), arg1, arg2)
            print("\n\n")
        }
        valueProfileFeatures.append(.init(pc: pcv, arg1: numericCast(arg1), arg2: numericCast(arg2)))
        /*
        
        let argxor = arg1 ^ arg2
        let argdist = UInt(UInt64(argxor).nonzeroBitCount + 1)

        let idx = ((pc & 4095) + 1) &* argdist
        _ = valueProfileMap.addValue(idx)
        */
    }
    
    
    static func handleGep(pc: NormalizedPC, idx: UInt) {
        gepFeatures.append(.init(pc: pc.value, arg: UInt64(idx))) // FIXME
    }
    
    static func resetMaps() {
        UnsafeMutableBufferPointer(rebasing: eightBitCounters[..<numPCs()]).assign(repeating: 0)
        indirectFeatures.removeAll(keepingCapacity: true)
        valueProfileFeatures.removeAll(keepingCapacity: true)
    }
    
    static var recording = false
}


extension RangeReplaceableCollection where Self: MutableCollection, Self: RandomAccessCollection, Element: Equatable, Index: Hashable {
    mutating func removeDuplicateAdjacentElements() {
        guard !isEmpty else { return }
        var cur = first!
        var toRemove: Set<Index> = []
        
        var i = index(after: startIndex)
        while i < endIndex {
            defer { formIndex(after: &i) }
            if self[i] == cur {
                toRemove.insert(i)
            } else {
                cur = self[i]
            }
        }
        let p = stablePartition(count: count, isSuffixElement: toRemove.contains)
        removeLast(self.distance(from: p, to: endIndex))
    }
    
    
    /// Moves all elements satisfying `isSuffixElement` into a suffix of the
    /// collection, preserving their relative order, and returns the start of the
    /// resulting suffix.
    ///
    /// - Complexity: O(n) where n is the number of elements.
    /// - Precondition: `n == self.count`
    fileprivate mutating func stablePartition(
        count n: Int, isSuffixElement: (Index) throws-> Bool
        ) rethrows -> Index {
        if n == 0 { return startIndex }
        if n == 1 {
            return try isSuffixElement(startIndex) ? startIndex : endIndex
        }
        let h = n / 2, i = index(startIndex, offsetBy: h)
        let j = try self[..<i].stablePartition(
            count: h, isSuffixElement: isSuffixElement)
        let k = try self[i...].stablePartition(
            count: n - h, isSuffixElement: isSuffixElement)
        return self[j..<k].rotate(shiftingToStart: i)
    }
    
    /// Rotates the elements of the collection so that the element
    /// at `middle` ends up first.
    ///
    /// - Returns: The new index of the element that was first
    ///   pre-rotation.
    /// - Complexity: O(*n*)
    @discardableResult
    public mutating func rotate(shiftingToStart middle: Index) -> Index {
        var m = middle, s = startIndex
        let e = endIndex
        
        // Handle the trivial cases
        if s == m { return e }
        if m == e { return s }
        
        // We have two regions of possibly-unequal length that need to be
        // exchanged.  The return value of this method is going to be the
        // position following that of the element that is currently last
        // (element j).
        //
        //   [a b c d e f g|h i j]   or   [a b c|d e f g h i j]
        //   ^             ^     ^        ^     ^             ^
        //   s             m     e        s     m             e
        //
        var ret = e // start with a known incorrect result.
        while true {
            // Exchange the leading elements of each region (up to the
            // length of the shorter region).
            //
            //   [a b c d e f g|h i j]   or   [a b c|d e f g h i j]
            //    ^^^^^         ^^^^^          ^^^^^ ^^^^^
            //   [h i j d e f g|a b c]   or   [d e f|a b c g h i j]
            //   ^     ^       ^     ^         ^    ^     ^       ^
            //   s    s1       m    m1/e       s   s1/m   m1      e
            //
            let (s1, m1) = _swapNonemptySubrangePrefixes(s..<m, m..<e)
            
            if m1 == e {
                // Left-hand case: we have moved element j into position.  if
                // we haven't already, we can capture the return value which
                // is in s1.
                //
                // Note: the STL breaks the loop into two just to avoid this
                // comparison once the return value is known.  I'm not sure
                // it's a worthwhile optimization, though.
                if ret == e { ret = s1 }
                
                // If both regions were the same size, we're done.
                if s1 == m { break }
            }
            
            // Now we have a smaller problem that is also a rotation, so we
            // can adjust our bounds and repeat.
            //
            //    h i j[d e f g|a b c]   or    d e f[a b c|g h i j]
            //         ^       ^     ^              ^     ^       ^
            //         s       m     e              s     m       e
            s = s1
            if s == m { m = m1 }
        }
        
        return ret
    }
    @inline(__always)
    internal mutating func _swapNonemptySubrangePrefixes(
        _ lhs: Range<Index>, _ rhs: Range<Index>
        ) -> (Index, Index) {
        _sanityCheck(!lhs.isEmpty)
        _sanityCheck(!rhs.isEmpty)
        
        var p = lhs.lowerBound
        var q = rhs.lowerBound
        repeat {
            swapAt(p, q)
            formIndex(after: &p)
            formIndex(after: &q)
        } while p != lhs.upperBound && q != rhs.upperBound
        
        return (p, q)
    }
}
