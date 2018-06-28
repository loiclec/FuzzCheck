
import Basic
import Files
import Foundation
import Fuzzer
import Utility

typealias Process = Foundation.Process
typealias URL = Foundation.URL

var (settings, workerSettings, world) = try parseArguments()

if case .minimize = workerSettings.command {
    try minimizeCommand(settings: settings, workerSettings: workerSettings, world: world)
} else if case .fuzz = workerSettings.command {
    try fuzzCommand(settings: settings, workerSettings: workerSettings, world: world)
} else {
    fatalError("Unsupported command \(workerSettings.command)")
}

