//
//  ArgumentsParser.swift
//  FuzzerJobsManager
//

import Basic
import Files
import Foundation
import Fuzzer

func parseArguments() throws -> (FuzzerManagerSettings, FuzzerSettings, CommandLineFuzzerWorldInfo) {
    
    let (parser, workerSettingsBinder, worldBinder, settingsBinder) = CommandLineFuzzerWorldInfo.argumentsParser()
    
    let res = try parser.parse(Array(CommandLine.arguments.dropFirst()))
    var workerSettings = FuzzerSettings()
    try workerSettingsBinder.fill(parseResult: res, into: &workerSettings)
    
    var settings = FuzzerManagerSettings()
    try settingsBinder.fill(parseResult: res, into: &settings)

    print(workerSettings)
    var world = CommandLineFuzzerWorldInfo()
    try worldBinder.fill(parseResult: res, into: &world)
    
    return (settings, workerSettings, world)
}
