//
//  FuzzerSensor.swift
//  FuzzCheck
//

/**
 A `FuzzerSensor` collects measurements that the fuzzer should optimize (e.g. code coverage)
 
 These measurements are expressed in terms of “Feature” (see `FuzzerSensorFeature` protocol).
 */
public protocol FuzzerSensor {
    associatedtype Feature: FuzzerSensorFeature

    mutating func resetCollectedFeatures()
    
    var isRecording: Bool { get set }
    
    func iterateOverCollectedFeatures(_ handle: (Feature) -> Void)
}

/**
 A FuzzerSensorFeature describes a single property about a run of the test function.
 It will be collected by a FuzzerSensor and analyzed by a Fuzzer.
 
 For example, this property could be that a specific line of code was reached,
 or that a specific comparison operation failed, etc.
 
 Each feature has an associated “score”, which measures its relative importance compared
 to the other features.
 */
public protocol FuzzerSensorFeature: Hashable {
    var score: Double { get }
}


