//
//  ArtifactsTest.swift
//  FuzzCheck
//


import XCTest
@testable import Fuzzer

class ArtifactsTests: XCTestCase {
    /*
    func testParse() {
        let s = "??kind-?complexity?-?hash-?index"
        let ext = ""
        
        let existing: Set<String> = [
            "43.7fffffffffffffff.0.json",
            "43.7fffffffffffffff.1.json",
            "43.7fffffffffffffff.2.json",
            "43.7fffffffffffffff.3.json",
            "43.7fffffffffffffff.4.json",
            "43.7fffffffffffffff.5.json",
        ]
        
        let schemaAtoms = ArtifactSchema.Name.Atom.read(from: s)
        let schema = ArtifactSchema.Name(components: schemaAtoms, ext: ext)
        let artNameInfo = ArtifactNameInfo(hash: Int.max, complexity: .init(43.327), kind: .crash)
        let artName = artNameInfo.name(following: schema)
        //print(artName)
        print(artName.fillGapToBeUnique(from: existing))
    }*/
}
