//
//  Artifact.swift
//  Fuzzer
//

import Files
import Foundation

public struct Artifact {
    let name: ArtifactNameWithoutIndex
    let data: Data
}

public struct ArtifactNameInfo: Hashable {
    let hash: Int
    let complexity: Complexity
    let kind: ArtifactKind
}

public enum ArtifactKind {
    case unit
    case timeout
    case crash
}

public struct ArtifactNameSchema: Hashable {
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
}

extension ArtifactNameInfo {
    func name(following schema: ArtifactNameSchema) -> ArtifactNameWithoutIndex {
        //precondition(!schema.atoms.isEmpty)
        var name = ""
        var gapForIndex: Range<String.Index>? = nil
        for a in schema.atoms {
            switch a {
            case .string(let s):
                name += s
            case .hash:
                name += hexString(hash)
            case .complexity:
                name += "\(Int(complexity.value.rounded()))"
            case .kind:
                name += "\(kind)"
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
        return ArtifactNameWithoutIndex(string: name, gapForIndex: gapForIndex!)
    }
}


extension ArtifactNameSchema.Atom: CustomStringConvertible {
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


extension ArtifactNameSchema.Atom {
    static func read(from s: inout Substring) -> ArtifactNameSchema.Atom? {
        guard let first = s.first else {
            return nil
        }
        let specials: [ArtifactNameSchema.Atom] = [.hash, .complexity, .index, .kind]
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
    public static func read(from s: String) -> [ArtifactNameSchema.Atom] {
        var subs = Substring(s)
        var res: [ArtifactNameSchema.Atom] = []
        while let a = read(from: &subs) {
            res.append(a)
        }
        return res
    }
}

