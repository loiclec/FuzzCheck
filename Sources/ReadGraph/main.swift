
import Foundation

import ModuleToTest
import ModuleToTestMutators

// struct Nothing: Hashable, Codable {}

let path = CommandLine.arguments[1]
let data = try! Data.init(contentsOf: URL.init(fileURLWithPath: path))
let decoder = JSONDecoder.init()
let g = try! decoder.decode(Graph<UInt8>.self, from: data)
// let g = try! decoder.decode(Graph<Nothing>.self, from: data)
print(g.dotDescription())
