
import Basic
import Foundation
import Fuzzer
import ModuleToTest
import ModuleToTestMutators
import Utility


extension RangeReplaceableCollection where Self: MutableCollection, Self: RandomAccessCollection, Element: Equatable, Index: Hashable {
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


struct Nothing: Hashable { }
extension Nothing: FuzzUnit {
    func complexity() -> Double {
        return 1.0
    }
    func hash() -> Int {
        return 0.hashValue
    }
}
struct NothingMutators: Mutators {
    func mutate(_ unit: inout Nothing, with mutator: Void, _ rand: inout Rand) -> Bool { return false }
    let weightedMutators: [(Mutator, UInt64)] = []
    typealias Mutated = Nothing
    typealias Mutator = Void
}

extension UInt8: FuzzUnit { }

struct GraphGenerator : FuzzUnitGenerator {
    typealias Unit = Graph<UInt8>
    typealias Mut = GraphMutators<UnsignedIntegerMutators<UInt8>>

    var mutators = GraphMutators(vertexMutators: UnsignedIntegerMutators.init(), initializeVertex: { r in r.byte() })
    func baseUnit() -> Unit {
         return Graph()
    }
    func initialUnits(_ r: inout Rand) -> [Unit] {
        return (1 ... 10).map { i in
            var g = Graph<UInt8>()
            for _ in 0 ..< (i * 10) {
                _ = mutators.mutate(&g, &r)
            }
            return g
        }
    }
}

func test(_ g: Graph<UInt8>) -> Bool {
     if
        g.count == 6,
        g.graph[0].data == 0x64,
        g.graph[1].data == 0x65,
        g.graph[2].data == 0x61,
        g.graph[3].data == 0x64,
        g.graph[4].data == 0x62,
        g.graph[5].data == 0x65,
        g.graph[0].edges.count == 2,
        g.graph[0].edges[0] == 1,
        g.graph[0].edges[1] == 2,
        g.graph[1].edges.count == 2,
        g.graph[1].edges[0] == 3,
        g.graph[1].edges[1] == 4,
        g.graph[2].edges.count == 1,
        g.graph[2].edges[0] == 5,
        g.graph[3].edges.count == 0,
        g.graph[4].edges.count == 0,
        g.graph[5].edges.count == 0
     {
        return false
     }
     else {
        return true
    }
}

let graphMutators = GraphMutators(vertexMutators: UnsignedIntegerMutators<UInt8>(), initializeVertex: { r in r.byte() })

try CommandLineFuzzer.launch(test: test, generator: GraphGenerator())
