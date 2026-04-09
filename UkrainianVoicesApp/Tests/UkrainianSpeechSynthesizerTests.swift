//
//  UkrainianSpeechSynthesizerTests.swift
//  RHVoiceUkrainianSynthesizerTests
//
//  Integration tests for VoiceOver provider
//

import XCTest
import AVFoundation
@testable import RHVoiceUkrainianSynthesizer

@available(iOS 16.0, *)
class UkrainianSpeechSynthesizerTests: XCTestCase {
    
    var synthesizer: UkrainianSpeechSynthesizer!
    
    override func setUp() {
        super.setUp()
        synthesizer = UkrainianSpeechSynthesizer()
    }
    
    override func tearDown() {
        synthesizer = nil
        super.tearDown()
    }
    
    func testSynthesizerExists() {
        XCTAssertNotNil(synthesizer, "Synthesizer should be created")
    }
    
    func testVoicesAreAvailable() {
        let voices = synthesizer.speechVoices
        XCTAssertFalse(voices.isEmpty, "Should have at least one voice")
        XCTAssertEqual(voices.count, 4, "Should have 4 Ukrainian voices")
    }
    
    func testVoiceNames() {
        let voices = synthesizer.speechVoices
        let voiceNames = voices.map { $0.name }
        
        XCTAssertTrue(voiceNames.contains("Anatol"), "Should have Anatol voice")
        XCTAssertTrue(voiceNames.contains("Natalia"), "Should have Natalia voice")
        XCTAssertTrue(voiceNames.contains("Marianna"), "Should have Marianna voice")
        XCTAssertTrue(voiceNames.contains("Volodymyr"), "Should have Volodymyr voice")
    }
    
    func testVoiceIdentifiers() {
        let voices = synthesizer.speechVoices
        
        for voice in voices {
            XCTAssertTrue(voice.identifier.hasPrefix("com.rhvoice.UkrainianVoices."),
                         "Voice identifier should have correct prefix")
        }
    }
    
    func testVoiceLanguages() {
        let voices = synthesizer.speechVoices
        
        for voice in voices {
            XCTAssertTrue(voice.primaryLanguages.contains("uk-UA"), 
                         "Voice should support Ukrainian language")
        }
    }
    
    func testSynthesisRequestHandling() {
        // Create a mock request
        let voice = synthesizer.speechVoices.first!
        
        // Note: AVSpeechSynthesisProviderRequest is difficult to mock
        // This test verifies the synthesizer can handle the protocol
        XCTAssertTrue(synthesizer.conforms(to: AVSpeechSynthesisProviderAudioUnit.self),
                     "Synthesizer should conform to AVSpeechSynthesisProviderAudioUnit")
    }
}
