
import Foundation

import ModuleToTest
import ModuleToTestMutators

// struct Nothing: Hashable, Codable {}

struct UnitInArtifact: Decodable {
    let unit: Graph<UInt8>
}

let path = CommandLine.arguments[1]
let data = try! Data.init(contentsOf: URL.init(fileURLWithPath: path))
let decoder = JSONDecoder.init()

let g = try! decoder.decode(UnitInArtifact.self, from: data)
// let g = try! decoder.decode(Graph<Nothing>.self, from: data)
print(g.unit.dotDescription())

