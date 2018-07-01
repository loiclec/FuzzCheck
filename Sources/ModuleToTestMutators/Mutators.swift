

import Fuzzer
import DefaultFuzzUnitGenerators
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
        let array = try Array<Pair<V, [Int]>>(from: decoder)
        for p in array {
            let vi = self.addVertex(p.a)
            for e in p.b {
                self.addEdge(from: vi, to: e)
            }
        }
    }
    public func encode(to encoder: Encoder) throws {
        try self.map { Pair($0.data, $0.edges) }.encode(to: encoder)
    }
}

extension Graph: FuzzUnit where V: FuzzUnit, V: Hashable {
    public func complexity() -> Double {
        precondition(totalSize >= 0)
        return 1 + Double(totalSize)
    }
    
    public func hash() -> Int {
        let h = reduce(into: Hasher()) { (h: inout Hasher, v: Vertex) in
            h.combine(v.data)
            h.combine(v.edges)
        }
        return h.finalize()
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
    
    public enum Mutator {
        case addVertices
        case addEdges
        case copySubset
        case splitEdge
        case addFriend
        case moveEdge
        case addEdge
        case removeEdge
        case addVertex
        case removeVertex
        case modifyVertexData
    }
    
    public func mutate(_ unit: inout Graph<VM.Mutated>, with mutator: GraphMutators<VM>.Mutator, _ rand: inout Rand) -> Bool {
        switch mutator {
        case .addVertices:
            return addVertices(&unit, &rand)
        case .addEdges:
            return addEdges(&unit, &rand)
        case .copySubset:
            return copySubset(&unit, &rand)
        case .splitEdge:
            return splitEdge(&unit, &rand)
        case .addFriend:
            return addFriend(&unit, &rand)
        case .moveEdge:
            return moveEdge(&unit, &rand)
        case .addEdge:
            return addEdge(&unit, &rand)
        case .removeEdge:
            return removeEdge(&unit, &rand)
        case .addVertex:
            return addVertex(&unit, &rand)
        case .removeVertex:
            return removeVertex(&unit, &rand)
        case .modifyVertexData:
            return modifyVertexData(&unit, &rand)
        }
    }
    
    func copySubset(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        var corresponding: [Int: Int] = [:]
        for _ in 0 ..< (1 ... x.count).randomElement(using: &r)! {
            let copiedVertexIdx = x.indices.randomElement(using: &r)!
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
        
        guard let fromIndex = x.indices.randomElement(using: &r) else {
            return false
        }
        let fromData = x.graph[fromIndex]
        
        guard let oldDestEdgeIndex = fromData.edges.indices.randomElement(using: &r) else {
            return false
        }
        
        let oldDest = fromData.edges[oldDestEdgeIndex]
        x.removeEdge(from: fromIndex, to: oldDestEdgeIndex)
        let newVertex = x.addVertex(initializeVertex(&r))
        x.addEdge(from: fromIndex, to: newVertex)
        x.addEdge(from: newVertex, to: oldDest)
        return true
    }
    
    func addFriend(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard let from = x.indices.randomElement(using: &r) else {
            return false
        }
        let newVertex = x.addVertex(initializeVertex(&r))
        x.addEdge(from: from, to: newVertex)
        return true
    }
    
    func moveEdge(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard let fromIndex = x.indices.randomElement(using: &r) else {
            return false
        }
        let fromData = x.graph[fromIndex]
        guard let oldDest = fromData.edges.indices.randomElement(using: &r) else {
            return false
        }
        x.removeEdge(from: fromIndex, to: oldDest)
        let newDest = x.indices.randomElement(using: &r)!
        x.addEdge(from: fromIndex, to: newDest)
        return true
    }
    
    func addEdge(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let vi = x.indices.randomElement(using: &r)!
        let vj = x.indices.randomElement(using: &r)!
        x.addEdge(from: vi, to: vj)
        return true
    }
    func addEdges(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard let vi = x.indices.randomElement(using: &r) else {
            return false
        }
        
        let count = (1 ... x.graph.count).randomElement(using: &r)!
        for _ in 0 ..< count {
            let vj = x.indices.randomElement(using: &r)!
            x.addEdge(from: vi, to: vj)
        }
        return true
    }
    
    func removeEdge(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard let vi = x.indices.randomElement(using: &r) else {
            return false
        }
        let v = x.graph[vi]
        guard let ei = v.edges.indices.randomElement(using: &r) else {
            return false
        }
        x.removeEdge(from: vi, to: ei)
        return true
    }
    
    func addVertex(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        _ = x.addVertex(initializeVertex(&r))
        return true
    }
    func addVertices(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        let count = (1 ... max(20, x.count)).randomElement(using: &r)!
        for _ in 0 ..< count {
            _ = x.addVertex(initializeVertex(&r))
        }
        return true
    }
    
    func removeVertex(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let i = x.graph.indices.randomElement(using: &r)!
        x.removeVertex(i)
        return true
    }
    
    func modifyVertexData(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        
        let i = x.graph.indices.randomElement(using: &r)!
        return vertexMutators.mutate(&x.graph[i].data, &r)
    }
    
    public let weightedMutators: [(Mutator, UInt)] = [
        (.addVertices, 5),
        (.addEdges, 10),
        (.addFriend, 30),
        (.moveEdge, 47),
        (.addEdge, 77),
        (.removeEdge, 87),
        (.addVertex, 97),
        (.removeVertex, 107),
        (.modifyVertexData, 157),
    ]
    
}

public struct GraphGenerator : FuzzUnitGenerator {
    public typealias Unit = Graph<UInt8>
    public typealias Mut = GraphMutators<IntegerMutators<UInt8>>
    
    public let mutators = GraphMutators(vertexMutators: IntegerMutators(), initializeVertex: { r in r.next() as UInt8 })
    public let baseUnit: Unit = Graph()

    public init() { }
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
    let weightedMutators: [(Mutator, UInt)] = []
    typealias Mutated = Nothing
    typealias Mutator = Void
}

extension UInt8: FuzzUnit { }
