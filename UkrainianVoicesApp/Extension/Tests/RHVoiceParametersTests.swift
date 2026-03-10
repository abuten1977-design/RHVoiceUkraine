//
//  RHVoiceParametersTests.swift
//  RHVoiceUkrainianSynthesizerTests
//
//  Unit tests for RHVoice parameters
//

import XCTest
@testable import RHVoiceUkrainianSynthesizer

class RHVoiceParametersTests: XCTestCase {
    
    func testVolumeParametersExist() {
        let params = RHVoiceParameters.volumeParameters()
        XCTAssertNotNil(params, "Volume parameters should exist")
        XCTAssertGreaterThan(params.max, params.min, "Max volume should be greater than min")
        XCTAssertGreaterThanOrEqual(params.defaultValue, params.min, "Default should be >= min")
        XCTAssertLessThanOrEqual(params.defaultValue, params.max, "Default should be <= max")
    }
    
    func testRateParametersExist() {
        let params = RHVoiceParameters.rateParameters()
        XCTAssertNotNil(params, "Rate parameters should exist")
        XCTAssertGreaterThan(params.max, params.min, "Max rate should be greater than min")
        XCTAssertGreaterThanOrEqual(params.defaultValue, params.min, "Default should be >= min")
        XCTAssertLessThanOrEqual(params.defaultValue, params.max, "Default should be <= max")
    }
    
    func testPitchParametersExist() {
        let params = RHVoiceParameters.pitchParameters()
        XCTAssertNotNil(params, "Pitch parameters should exist")
        XCTAssertGreaterThan(params.max, params.min, "Max pitch should be greater than min")
        XCTAssertGreaterThanOrEqual(params.defaultValue, params.min, "Default should be >= min")
        XCTAssertLessThanOrEqual(params.defaultValue, params.max, "Default should be <= max")
    }
    
    func testParameterRanges() {
        let volume = RHVoiceParameters.volumeParameters()
        let rate = RHVoiceParameters.rateParameters()
        let pitch = RHVoiceParameters.pitchParameters()
        
        // Volume should be 0-1 range typically
        XCTAssertEqual(volume.min, 0.0, accuracy: 0.01, "Volume min should be ~0")
        XCTAssertEqual(volume.max, 1.0, accuracy: 0.01, "Volume max should be ~1")
        
        // Rate should allow slower and faster speech
        XCTAssertLessThan(rate.min, 1.0, "Rate min should allow slower speech")
        XCTAssertGreaterThan(rate.max, 1.0, "Rate max should allow faster speech")
        
        // Pitch should allow lower and higher pitch
        XCTAssertLessThan(pitch.min, 1.0, "Pitch min should allow lower pitch")
        XCTAssertGreaterThan(pitch.max, 1.0, "Pitch max should allow higher pitch")
    }
}
