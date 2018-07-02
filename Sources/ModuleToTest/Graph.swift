//
//  Graph.swift
//  BinaryCoder
//
//  Created by Loïc Lecrenier on 08/03/2018.
//

/// Append-only simple graph

public struct Graph <V> {
    
    public struct Vertex {
        public var data: V
        public var edges: [Int]
    }
    
    public var graph: [Vertex]
    
    public var totalSize: Int
}

extension Graph {
    public init() {
        self.graph = []
        self.totalSize = 0
    }
}

extension Graph {
    public mutating func addVertex(_ data: V) -> Int {
        let index = graph.endIndex
        self.graph.append(Vertex(data: data, edges: []))
        self.totalSize += 1
        return index
    }
    public mutating func addEdge(from: Int, to: Int) {
        totalSize += 1
        self.graph[from].edges.append(to)
    }
    public mutating func removeVertex(_ idx: Int) {
        graph.remove(at: idx)
        totalSize -= 1
        for i in graph.indices {
            let before = graph[i].edges.count
            graph[i].edges.removeAll(where: { $0 == idx })
            let after = graph[i].edges.count
            totalSize -= before - after
            for j in graph[i].edges.indices {
                if graph[i].edges[j] > idx {
                    graph[i].edges[j] -= 1
                }
            }
        }
    }
    public mutating func removeEdge(from: Int, to: Int) {
        graph[from].edges.remove(at: to)
        totalSize -= 1
    }
}

extension Graph: Collection {
    public subscript(index: Int) -> Vertex {
        get {
            return self.graph[index]
        }
    }
    
    public var startIndex: Int {
        return graph.startIndex
    }
    
    public var endIndex: Int {
        return graph.endIndex
    }
    
    public var indices: CountableRange<Int> {
        return startIndex ..< endIndex
    }
    
    public var isEmpty: Bool {
        return graph.isEmpty
    }
    
    public var count: Int {
        return graph.count
    }
    
    public func index(after i: Int) -> Int {
        return i.advanced(by: 1)
    }
}

extension Graph {
    
    public func makeBreadthFirstIterator(source: Int) -> BreadthFirstIterator {
        return BreadthFirstIterator(graph: self, source: source)
    }
    
    public struct BreadthFirstIterator : IteratorProtocol, Sequence {
        
        struct VertexAttributes {
            enum Color { case white, gray, black }
            
            var depth: Int
            var predecessor: Int?
            var color: Color
            
            static var `default`: VertexAttributes {
                return VertexAttributes(depth: Int.max, predecessor: nil, color: .white)
            }
        }
        
        var graph: Graph
        var attributes: [VertexAttributes]
        var queue: [Int]
        
        init(graph: Graph, source: Int) {
            self.graph = graph
            self.attributes = Array(repeating: .default, count: graph.graph.count)
            self.queue = [source]
            
            attributes[source].color = .gray
            attributes[source].depth = 0
        }
        
        public mutating func next() -> Int? {
            guard !queue.isEmpty else { return nil }
            
            let u = queue.removeLast()
            let depth = attributes[u].depth
            
            for v in graph[u].edges where attributes[v].color == .white {
                
                attributes[v].color = .gray
                attributes[v].depth = depth + 1
                attributes[v].predecessor = u
                
                queue.append(v)
            }
            attributes[u].color = .black
            
            return u
        }
        
        public func makeIterator() -> BreadthFirstIterator {
            return self
        }
    }
}

extension Graph {
    
    public struct DepthFirstSearched <D, F, E> {
        
        struct VertexAttributes {
            var color: Color
            var predecessor: Int?
        }
        
        enum Color { case white, gray, black }
        
        typealias DiscoverVertex = (Int, Int, inout D) -> ()
        typealias FinishVertex = (Int, Int, inout F) -> ()
        typealias VisitEdge = (_ source: Int, _ destination: Int, _ attributesOfDestination: VertexAttributes, inout E) -> ()
        
        let graph: Graph
        
        var attributes: [VertexAttributes]
        
        var discoverAcc: D
        var finishAcc: F
        var edgesAcc: E
        
        init(graph: Graph, rootVertices: [Int]? = nil, discoverAcc: D, finishAcc: F, edgesAcc: E, discover: DiscoverVertex, finish: FinishVertex, edge: VisitEdge) {
            self.graph = graph
            self.attributes = Array(repeating: .init(color: .white, predecessor: nil), count: graph.graph.count)
            
            self.discoverAcc = discoverAcc
            self.finishAcc = finishAcc
            self.edgesAcc = edgesAcc
            
            var time = 0
            for u in (rootVertices.map(AnySequence.init) ?? AnySequence(graph.indices)) where attributes[u].color == .white {
                visit(u, &time, discover, finish, edge)
            }
        }
        
        mutating func visit(_ u: Int, _ time: inout Int, _ discover: DiscoverVertex, _ finish: FinishVertex, _ edge: VisitEdge) {
            
            attributes[u].color = .gray
            time += 1
            
            discover(u, time, &discoverAcc)
            
            for v in graph[u].edges {
                edge(u, v, attributes[v], &edgesAcc)
                if attributes[v].color == .white {
                    attributes[v].predecessor = u
                    visit(v, &time, discover, finish, edge)
                }
            }
            
            attributes[u].color = .black
            time += 1
            finish(u, time, &finishAcc)
        }
        
        func forestVertices() -> [Set<Int>] {
            var forest: [Set<Int>] = []
            func inForest(_ i: Int) -> Int? {
                return forest.index {$0.contains(i)}
            }
            Loop: for (i, a) in zip(attributes.indices, attributes) {
                if let _ = inForest(i) {
                    continue
                } else {
                    var cur = a
                    var s: Set<Int> = [i]
                    while let pred = cur.predecessor {
                        if let fi = inForest(pred) {
                            forest[fi].formUnion(s)
                            continue Loop
                        } else {
                            s.insert(pred)
                        }
                        cur = attributes[pred]
                    }
                    forest.append(s)
                }
            }
            return forest
        }
    }
}

extension Graph {
    public func isLargeAndCyclic() -> Bool {
        guard graph.count >= 5 else { return false }
        var set = Set<Int>()
        for i in graph.indices {
            guard graph[i].edges.count == 1, graph[i].edges[0] != i, !set.contains(graph[i].edges[0]) else {
                return false
            }
            set.insert(graph[i].edges[0])
        }
        return self.stronglyConnectedComponents().count == 1
    }
}

extension Graph {
    public func topologicallySortedVertices() -> [Int] {
        let dps = Graph.DepthFirstSearched<Void, [Int], Void>(
            graph: self,
            discoverAcc: (),
            finishAcc: [],
            edgesAcc: (),
            discover: { _, _, _ in return },
            finish: { (index: Int, _, vertices: inout [Int]) in
                vertices.append(index)
        },
            edge:  { _, _, _, _ in return }
        )
        return dps.finishAcc.reversed()
    }
    
    public func isTree() -> Bool {
        let dps = Graph.DepthFirstSearched<Void, Void, Bool>(
            graph: self,
            discoverAcc: (),
            finishAcc: (),
            edgesAcc: true,
            discover: { _, _, _ in return },
            finish: { _, _, _ in return },
            edge: { (_, _, attributes: DepthFirstSearched.VertexAttributes, tree: inout Bool) in
                tree = (tree && attributes.color == .white)
        }
        )
        return dps.edgesAcc
    }
    
    public func isAcyclic() -> Bool {
        let dps = Graph.DepthFirstSearched<Void, Void, Bool>(
            graph: self,
            discoverAcc: (),
            finishAcc: (),
            edgesAcc: true,
            discover: { _, _, _ in return },
            finish: { _, _, _ in return },
            edge: { (_, _, attributes: DepthFirstSearched.VertexAttributes, acyclic: inout Bool) in
                acyclic = (acyclic && attributes.color != .gray)
        }
        )
        return dps.edgesAcc
    }
}

extension Graph {
    public func transposed() -> Graph {
        var t = Graph()
        for i in self.indices {
            let i2 = t.addVertex(self[i].data)
            assert(i == i2)
        }
        for i in self.indices {
            for j in self[i].edges {
                t.addEdge(from: j, to: i)
            }
        }
        return t
    }
}

extension Graph {
    public func dotDescription() -> String {
        let vertices = zip(graph.indices, graph).map { (i, v) in
            "\n\t\"\(i). \(v.data)\";" + v.edges.map { edge in
                "\n\t\"\(i). \(v.data)\" -> \"\(edge). \(graph[edge].data)\";"
                }.joined()
            }.joined()
        return """
        digraph G {
        \(vertices)
        }
        """
    }
}

extension Graph {
    public func successors(of nodeIdx: Int) -> Set<Int> {
        var successors: Set<Int> = [nodeIdx]
        var queue: [Int] = [nodeIdx]
        
        while !queue.isEmpty {
            let source = queue.removeLast()
            for next in graph[source].edges where !successors.contains(next) {
                queue.append(next)
                successors.insert(next)
            }
        }
        
        return successors
    }
    
    // TODO: wrong!
    public func stronglyConnectedComponents() -> [[Int]] {
        let dps = Graph.DepthFirstSearched<Void, [Int], Void>(
            graph: self,
            discoverAcc: (),
            finishAcc: Array(repeating: Int.max, count: count),
            edgesAcc: (),
            discover: {_, _, _ in },
            finish: { (index: Int, time: Int, times: inout [Int]) in
                times[index] = time
        },
            edge: {_, _, _, _ in })
        
        let t = self.transposed()
        let vertices = self.indices
            .sorted(by: { dps.finishAcc[$0] > dps.finishAcc[$1] })
        
        
        let dpst = Graph.DepthFirstSearched<Void, Void, Void>.init(
            graph: t,
            rootVertices: vertices,
            discoverAcc: (),
            finishAcc: (),
            edgesAcc: (),
            discover: {_, _, _ in },
            finish: {_, _, _ in },
            edge: {_, _, _, _ in }
        )
        
        let f = dpst.forestVertices()
        return f.map { set in set.map { Int($0) } }
    }
}

extension Graph: ExpressibleByDictionaryLiteral where V: Hashable {
    public typealias Key = V
    public typealias Value = V
    
    public init(dictionaryLiteral elements: (V, V)...) {
        self.graph = []
        self.totalSize = 0
        var cache: [V: Int] = [:]
        
        for (from, to) in elements {
            let fromIndex = cache[from] ?? addVertex(from)
            cache[from] = fromIndex
            
            let toIndex = cache[to] ?? addVertex(to)
            cache[to] = toIndex
            
            self.addEdge(from: fromIndex, to: toIndex)
        }
    }
}
