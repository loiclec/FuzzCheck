//
//  FuzzerSensor.swift
//  FuzzCheck
//

public protocol FuzzerSensor {
    associatedtype Feature: FuzzerSensorFeature

    mutating func resetCollectedFeatures()
    
    var isRecording: Bool { get set }
    
    func collectFeatures(_ handle: (Feature) -> Void)
}

public protocol FuzzerSensorFeature {
    associatedtype Reduced: Hashable
    var reduced: Reduced { get }
    var score: Double { get }
}


