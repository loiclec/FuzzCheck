

import Fuzzer
import ModuleToTest

struct Pair <A, B> : Codable where A: Codable, B: Codable {
    let a : A
    let b : B
    
    init(_ a: A, _ b: B) {
        self.a = a
        self.b = b
    }
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.a = try container.decode(A.self)
        self.b = try container.decode(B.self)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(a)
        try container.encode(b)
    }
}

extension Graph: Codable where V: Codable {
    public init(from decoder: Decoder) throws {
        self.init()
        var container = try decoder.unkeyedContainer()
        let array = try container.decode(Array<Pair<V, [Int]>>.self)
        for p in array {
            let vi = self.addVertex(p.a)
            for e in p.b {
                self.addEdge(from: vi, to: e)
            }
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.map { Pair($0.data, $0.edges) })
    }
}

extension Graph: FuzzInput where V: FuzzInput, V: Hashable {
    public func complexity() -> Double {
        precondition(totalSize >= 0)
        return 1 + Double(totalSize)
    }
    
    public func hash() -> Int {
        return reduce(1.hashValue) { ((($0 &* 65371) ^ $1.data.hash()) &* 65371) ^ $1.edges.hash() }
    }
}

public struct GraphMutators <VM: Mutators> : Mutators where VM.Mutated: Hashable {
    public typealias Mutated = Graph<VM.Mutated>
    
    public let vertexMutators: VM
    public let initializeVertex: (_ r: inout Rand) -> VM.Mutated
    
    public init(vertexMutators: VM, initializeVertex: @escaping (_ r: inout Rand) -> VM.Mutated) {
        self.vertexMutators = vertexMutators
        self.initializeVertex = initializeVertex
    }
    
    func copySubset(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        var corresponding: [Int: Int] = [:]
        for _ in 0 ..< r.positiveInt(x.count) {
            let copiedVertexIdx = r.positiveInt(x.count)
            if corresponding[copiedVertexIdx] == nil {
                corresponding[copiedVertexIdx] = x.addVertex(x.graph[copiedVertexIdx].data)
            }
            for e in x.graph[copiedVertexIdx].edges {
                if corresponding[e] == nil {
                    corresponding[e] = x.addVertex(x.graph[e].data)
                }
            }
        }
        for (original, new) in corresponding {
            for e in x.graph[original].edges {
                if let f = corresponding[e] { // copy the edge if its destination vertex has also been copied
                    x.addEdge(from: new, to: f)
                }
            }
        }
        return true
    }
    
    func splitEdge(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let vi = r.positiveInt(x.count)
        let v = x.graph[vi]
        guard !v.edges.isEmpty else { return false }
        let ei = r.positiveInt(v.edges.count)
        let e = v.edges[ei]
        x.removeEdge(from: vi, to: ei)
        let newV = x.addVertex(initializeVertex(&r))
        x.addEdge(from: vi, to: newV)
        x.addEdge(from: newV, to: e)
        return true
    }
    
    func addFriend(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let vi = r.positiveInt(x.count)
        let newV = x.addVertex(initializeVertex(&r))
        x.addEdge(from: vi, to: newV)
        x.addEdge(from: newV, to: vi)
        return true
    }
    
    func moveEdge(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let vi = r.positiveInt(x.count)
        let v = x.graph[vi]
        guard !v.edges.isEmpty else { return false }
        let ei = r.positiveInt(v.edges.count)
        x.removeEdge(from: vi, to: ei)
        let otherV = r.positiveInt(x.count)
        x.addEdge(from: vi, to: otherV)
        return true
    }
    
    func addEdge(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let vi = r.positiveInt(x.count)
        let vj = r.positiveInt(x.count)
        x.addEdge(from: vi, to: vj)
        return true
    }
    
    func removeEdge(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let vi = r.positiveInt(x.count)
        let v = x.graph[vi]
        guard !v.edges.isEmpty else { return false }
        let ei = r.positiveInt(v.edges.count)
        x.removeEdge(from: vi, to: ei)
        return true
    }
    
    func addVertex(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        _ = x.addVertex(initializeVertex(&r))
        return true
    }
    
    func removeVertex(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let i = r.int(inside: x.graph.indices)
        x.removeVertex(i)
        return true
    }
    
    func modifyVertexData(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        
        let i = r.int(inside: x.graph.indices)
        return vertexMutators.mutate(&x.graph[i].data, &r)
    }
    
    public func weightedMutators(for x: Mutated) -> [((inout Mutated, inout Rand) -> Bool, UInt64)] {
        return [
            (self.copySubset, 5),
            (self.splitEdge, 5),
            (self.addFriend, 5),
            (self.moveEdge, 5),
            (self.addEdge, 10),
            (self.removeEdge, 10),
            (self.addVertex, 10),
            (self.removeVertex, 10),
            (self.modifyVertexData, 100),
        ]
    }
}

extension RandomAccessCollection where Self: MutableCollection, Self: RangeReplaceableCollection {
    mutating func removeAll(where match: (Element) -> Bool) {
        guard !self.isEmpty else { return }
        
        var limit = startIndex
        for j in indices where !match(self[j]) {
            swapAt(limit, j)
            formIndex(after: &limit)
        }
        let removeFrom = limit
        
        formIndex(after: &limit)
        if limit < endIndex {
            swapAt(limit, index(before: endIndex))
        }
        
        removeLast(distance(from: removeFrom, to: endIndex))
    }
}

