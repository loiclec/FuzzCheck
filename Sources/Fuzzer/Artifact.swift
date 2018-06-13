//
//  Artifact.swift
//  Fuzzer
//

import Files
import Foundation

public struct Artifact <Unit: Codable> {
    let name: ArtifactNameWithoutIndex
    let content: Content

    
    public struct Content {
        let unit: Unit
        
        let features: [Feature]?
        let coverageScore: Feature.Coverage.Score?
        let hash: Int?
        let complexity: Complexity?
        let kind: ArtifactKind?
    }
}

public struct ArtifactSchema {
    public var name: Name
    public var content: Content
    
    public struct Name: Hashable {
        public enum Atom: Hashable {
            case string(String)
            case hash
            case complexity
            case index
            case kind
        }
        
        public var atoms: [Atom]
        public var ext: String?
    }
    
    public struct Content {
        let features: Bool
        let coverageScore: Bool
        let hash: Bool
        let complexity: Bool
        let kind: Bool
    
        init(features: Bool, coverageScore: Bool, hash: Bool, complexity: Bool, kind: Bool) {
           self.features = features
           self.coverageScore = coverageScore
           self.hash = hash
           self.complexity = complexity
           self.kind = kind
        }
    }
}

extension Artifact.Content {
    init(schema: ArtifactSchema.Content, unit: Unit, features: [Feature]?, coverage: Feature.Coverage.Score?, hash: Int?, complexity: Complexity?, kind: ArtifactKind) {
        self.unit = unit
        self.features = schema.features ? features : nil
        self.coverageScore = schema.coverageScore ? coverage : nil
        self.hash = schema.hash ? hash : nil
        self.complexity = schema.complexity ? complexity : nil
        self.kind = schema.kind ? kind : nil
    }
}

public struct ArtifactNameInfo: Hashable {
    let hash: Int
    let complexity: Complexity
    let kind: ArtifactKind
}

public enum ArtifactKind: String, Codable {
    case unit
    case timeout
    case crash
}

public struct ArtifactNameWithoutIndex: Hashable {
    let string: String
    let gapForIndex: Range<String.Index>
    
    func fillGap(with index: Int) -> String {
        var s = string
        s.replaceSubrange(gapForIndex, with: "\(index)")
        return s
    }
    func fillGapToBeUnique(from set: Set<String>) -> String {
        // in practice very few loop iterations will be performed
        for i in 0... {
            let candidate = fillGap(with: i)
            if !set.contains(candidate) { return candidate }
        }
        fatalError()
    }
    
    init(string: String, gapForIndex: Range<String.Index>) {
        self.string = string
        self.gapForIndex = gapForIndex
    }
    
    init(schema: ArtifactSchema.Name, info: ArtifactNameInfo) {
        //precondition(!schema.atoms.isEmpty)
        var name = ""
        var gapForIndex: Range<String.Index>? = nil
        for a in schema.atoms {
            switch a {
            case .string(let s):
                name += s
            case .hash:
                name += hexString(info.hash)
            case .complexity:
                name += "\(Int(info.complexity.value.rounded()))"
            case .kind:
                name += "\(info.kind)"
            case .index:
                gapForIndex = name.endIndex ..< name.endIndex
            }
        }
        if gapForIndex == nil {
            gapForIndex = name.endIndex ..< name.endIndex
        }
        if let ext = schema.ext, !ext.isEmpty {
            name += ".\(ext)"
        }
        self.init(string: name, gapForIndex: gapForIndex!)
    }
}

extension ArtifactSchema.Name.Atom: CustomStringConvertible {
    public var description: String {
        switch self {
        case .string(let s):
            return s
        case .hash:
            return "?hash"
        case .complexity:
            return "?complexity"
        case .index:
            return "?index"
        case .kind:
            return "?kind"
        }
    
    }
}

extension ArtifactSchema.Name.Atom {
    static func read(from s: inout Substring) -> ArtifactSchema.Name.Atom? {
        guard let first = s.first else {
            return nil
        }
        let specials: [ArtifactSchema.Name.Atom] = [.hash, .complexity, .index, .kind]
        for special in specials {
            if s.starts(with: special.description) {
                defer { s = s.dropFirst(special.description.count) }
                return special
            }
        }
        // No matches. Return a simple string
        guard let nextQMark = s.dropFirst().firstIndex(of: "?") else {
            defer { s = s[s.endIndex ..< s.endIndex] }
            return .string(String(s))
        }
        defer { s = s.suffix(from: nextQMark) }
        return .string(String(s.prefix(upTo: nextQMark)))
    }
    public static func read(from s: String) -> [ArtifactSchema.Name.Atom] {
        var subs = Substring(s)
        var res: [ArtifactSchema.Name.Atom] = []
        while let a = read(from: &subs) {
            res.append(a)
        }
        return res
    }
}

extension Artifact.Content: Codable {
    enum CodingKey: Swift.CodingKey {
        case unit
        case complexity
        case hash
        case coverage
        case features
        case kind
    }
    
    public func encode(to encoder: Encoder) throws {
        if self.complexity == nil, self.coverageScore == nil, self.hash == nil, self.kind == nil, self.features == nil {
            try unit.encode(to: encoder)
        } else {
            var container = encoder.container(keyedBy: CodingKey.self)
            try container.encode(unit, forKey: .unit)
            try container.encodeIfPresent(complexity, forKey: .complexity)
            try container.encodeIfPresent(coverageScore, forKey: .coverage)
            try container.encodeIfPresent(hash, forKey: .hash)
            try container.encodeIfPresent(kind, forKey: .kind)
            try container.encodeIfPresent(features, forKey: .features)
        }
    }
    public init(from decoder: Decoder) throws {
        if let unit = try? Unit(from: decoder) {
            self.unit = unit
            self.complexity = nil
            self.coverageScore = nil
            self.hash = nil
            self.features = nil
            self.kind = nil
        } else {
            let container = try decoder.container(keyedBy: CodingKey.self)
            self.unit = try container.decode(Unit.self, forKey: .unit)
            self.complexity = try container.decodeIfPresent(Complexity.self, forKey: .complexity)
            self.coverageScore = try container.decodeIfPresent(Feature.Coverage.Score.self, forKey: .coverage)
            self.hash = try container.decodeIfPresent(Int.self, forKey: .hash)
            self.features = try container.decodeIfPresent(Array<Feature>.self, forKey: .features)
            self.kind = try container.decodeIfPresent(ArtifactKind.self, forKey: .kind)
        }
    }
}
