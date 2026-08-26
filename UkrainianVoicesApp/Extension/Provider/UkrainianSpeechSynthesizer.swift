import AVFoundation
import AVFAudio
import CoreAudio
import CoreMedia
import Foundation
import RHVoiceBridge
import os.log

private let paramLog = OSLog(subsystem: "com.rhvoice.UkrainianVoices", category: "params")
private let apostropheLog = OSLog(subsystem: "com.rhvoice.UkrainianVoices", category: "apostrophe")
private let numberDiagLog = OSLog(subsystem: "com.rhvoice.UkrainianVoices", category: "number-diag")



// «Розширена діагностика» вмикається перемикачем у застосунку (App Group defaults).
// Читання UserDefaults не блокує аудіо-потік: значення кешує cfprefsd — на відміну
// від containerURL/stat, які на macOS 26 можуть зависнути (task-082/086).
private let rhDiagDefaults = UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)

private func rhExtendedDiagnosticsEnabled() -> Bool {
    rhDiagDefaults?.bool(forKey: RHVoiceSharedSettings.extendedDiagnosticsKey) ?? false
}

// «Читати дати словами»: відсутність ключа = увімкнено (типова поведінка).
private func rhDatesAsWordsEnabled() -> Bool {
    guard let defaults = rhDiagDefaults,
          defaults.object(forKey: RHVoiceSharedSettings.datesAsWordsKey) != nil else { return true }
    return defaults.bool(forKey: RHVoiceSharedSettings.datesAsWordsKey)
}

private func rhTimeAsWordsEnabled() -> Bool {
    guard let defaults = rhDiagDefaults,
          defaults.object(forKey: RHVoiceSharedSettings.timeAsWordsKey) != nil else { return true }
    return defaults.bool(forKey: RHVoiceSharedSettings.timeAsWordsKey)
}

private func rhAbbreviationsAsWordsEnabled() -> Bool {
    guard let defaults = rhDiagDefaults,
          defaults.object(forKey: RHVoiceSharedSettings.abbreviationsAsWordsKey) != nil else { return true }
    return defaults.bool(forKey: RHVoiceSharedSettings.abbreviationsAsWordsKey)
}

private func rhAbbreviationDictionaryEnabled() -> Bool {
    guard let defaults = rhDiagDefaults,
          defaults.object(forKey: RHVoiceSharedSettings.abbreviationDictionaryEnabledKey) != nil else { return true }
    return defaults.bool(forKey: RHVoiceSharedSettings.abbreviationDictionaryEnabledKey)
}

private func rhPhoneNumberProcessingEnabled() -> Bool {
    guard let defaults = rhDiagDefaults,
          defaults.object(forKey: RHVoiceSharedSettings.phoneNumberProcessingKey) != nil else { return true }
    return defaults.bool(forKey: RHVoiceSharedSettings.phoneNumberProcessingKey)
}

private func rhPhoneNumberReadingMode() -> RHVoicePhoneNumberReadingMode {
    guard let defaults = rhDiagDefaults,
          let raw = defaults.string(forKey: RHVoiceSharedSettings.phoneNumberReadingModeKey),
          let mode = RHVoicePhoneNumberReadingMode(rawValue: raw) else { return .groups }
    return mode
}

private func rhLog(_ msg: @autoclosure () -> String) {
    #if DEBUG
    let text = msg()
    text.withCString { RHVoiceDebugLogString($0) }
    #else
    guard rhExtendedDiagnosticsEnabled() else { return }
    let text = msg()
    text.withCString { RHVoiceDebugLogString($0) }
    #endif
}

private func apostropheDiagLog(_ msg: @autoclosure () -> String) {
    #if DEBUG
    let text = msg()
    rhLog(text)
    os_log(.info, log: apostropheLog, "%@", text as NSString)
    #endif
}

@available(iOS 16.0, macOS 13.0, *)
@objc(UkrainianSpeechSynthesizer)
public final class UkrainianSpeechSynthesizer: AVSpeechSynthesisProviderAudioUnit {
    private lazy var rhvoiceEngine: RHVoiceEngine = RHVoiceEngine()
    private let outputBus: AUAudioUnitBus
    private var _outputBusses: AUAudioUnitBusArray!

    // eSpeak-style: flat array + offset + semaphore
    private var output: [Float] = []
    private var outputOffset: Int = 0
    private var outputMutex = DispatchSemaphore(value: 1)
    private var isSynthesizing = false
    private let synthesisQueue = DispatchQueue(label: "com.rhvoice.UkrainianVoices.synthesis", qos: .userInitiated)
    private var synthesisGeneration: UInt64 = 0
    private let sharedSettingsCache = RHVoiceSharedSettingsSnapshotCache()

    private static let staticVoices: [AVSpeechSynthesisProviderVoice] = [
        AVSpeechSynthesisProviderVoice(name: "Anatol", identifier: "com.rhvoice.UkrainianVoices.anatol",
            primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
        AVSpeechSynthesisProviderVoice(name: "Natalia", identifier: "com.rhvoice.UkrainianVoices.natalia",
            primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
        AVSpeechSynthesisProviderVoice(name: "Marianna", identifier: "com.rhvoice.UkrainianVoices.marianna",
            primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
        AVSpeechSynthesisProviderVoice(name: "Volodymyr", identifier: "com.rhvoice.UkrainianVoices.volodymyr",
            primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
    ]
    private static var didLogNumberDiagActiveBuild = false

    @objc
    public override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        let basicDescription = AudioStreamBasicDescription(
            mSampleRate: 24000.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let format = AVAudioFormat(cmAudioFormatDescription: try CMAudioFormatDescription(audioStreamBasicDescription: basicDescription))
        self.outputBus = try AUAudioUnitBus(format: format)

        try super.init(componentDescription: componentDescription, options: options)

        self._outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        // Do not restore AUParameterTree here. It regressed the macOS VoiceOver rotor
        // into announcing numeric percentages instead of voices (fixed in 151a4aec,
        // accidentally restored in ed59926a, removed again by task-087). VoiceOver
        // rate/volume/pitch arrive through SSML prosody, and app settings arrive
        // through the App Group snapshot cache.
        rhLog("EXT_DIAG synthesizer init")
        self.sharedSettingsCache.start()
        RHVoiceDownloadedVoicesCache.shared.start()
        AbbreviationDictionaryCache.shared.start()
        self.startEngineWarmup()
    }

    private func startEngineWarmup() {
        self.synthesisQueue.async { [weak self] in
            guard let self else { return }
            let warmupStart = CFAbsoluteTimeGetCurrent()
            rhLog("WARMUP started")
            _ = self.rhvoiceEngine
            rhLog("WARMUP done elapsedMs=\(Self.elapsedMs(since: warmupStart))")
        }
    }

    public override var outputBusses: AUAudioUnitBusArray { _outputBusses }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        _ = self.rhvoiceEngine
    }

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get { Self.publishedProviderVoices() }
        set { }
    }

    /// System enumeration must use the catalog durably published by the app;
    /// scanning the downloaded-voice tree here lost dynamic voices on iPhone.
    private static func publishedProviderVoices() -> [AVSpeechSynthesisProviderVoice] {
        publishedVoiceDescriptors(logSource: true).map { descriptor in
            AVSpeechSynthesisProviderVoice(
                name: descriptor.name,
                identifier: descriptor.identifier,
                primaryLanguages: [descriptor.language],
                supportedLanguages: [descriptor.language]
            )
        }
    }

    /// The descriptor used for system enumeration must also resolve the
    /// profile during rendering. Otherwise a just-downloaded English voice can
    /// be visible in VoiceOver while the extension's directory cache is still
    /// empty and silently falls back to Anatol.
    private static func publishedVoiceDescriptors(logSource: Bool = false) -> [RHVoiceVoiceDescriptor] {
        #if os(iOS)
        let catalog = RHVoicePublishedVoiceCatalog.loadPublished()
        let descriptors = catalog?.descriptors ?? RHVoiceSharedSettings.builtInVoiceCatalog
        if logSource {
            NSLog("VOICE_CATALOG_DIAG source=published-ios revision=%d count=%d ids=%@", catalog?.revision ?? 0, descriptors.count, descriptors.map(\.identifier).joined(separator: ","))
        }
        #else
        let descriptors = RHVoiceSharedSettings.builtInVoiceCatalog + RHVoiceDownloadedVoicesCache.shared.currentVoicesEnsuringFirstLoad()
        #endif
        return descriptors
    }

    // MARK: - Render (exactly like eSpeak)

    private func performRender(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AUAudioFrameCount,
        outputBusNumber: Int,
        outputAudioBufferList: UnsafeMutablePointer<AudioBufferList>,
        renderEvents: UnsafePointer<AURenderEvent>?,
        renderPull: AURenderPullInputBlock?
    ) -> AUAudioUnitStatus {
        let unsafeBuffer = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
        let frames = unsafeBuffer[0].mData!.assumingMemoryBound(to: Float.self)
        let intFrameCount = Int(frameCount)
        frames.assign(repeating: 0, count: intFrameCount)

        self.outputMutex.wait()
        var available = max(self.output.count - self.outputOffset, 0)
        var stillSynthesizing = self.isSynthesizing
        self.outputMutex.signal()

        if available < intFrameCount && stillSynthesizing {
            let ready = self.pauseUntilRenderReady(needFrames: intFrameCount)

            self.outputMutex.wait()
            available = max(self.output.count - self.outputOffset, 0)
            stillSynthesizing = self.isSynthesizing
            self.outputMutex.signal()

            rhLog("RENDER_WAIT perform ready=\(ready ? 1 : 0) available=\(available) stillSynthesizing=\(stillSynthesizing ? 1 : 0)")
        }

        if available <= 0 {
            outputAudioBufferList.pointee.mBuffers.mDataByteSize = UInt32(intFrameCount * MemoryLayout<Float>.size)
            
            if stillSynthesizing {
                actionFlags.pointee = .offlineUnitRenderAction_Render
            } else {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
            }
            return noErr
        }

        self.outputMutex.wait()
        available = max(self.output.count - self.outputOffset, 0)
        stillSynthesizing = self.isSynthesizing

        if available <= 0 {
            self.outputMutex.signal()

            outputAudioBufferList.pointee.mBuffers.mDataByteSize = UInt32(intFrameCount * MemoryLayout<Float>.size)

            if stillSynthesizing {
                actionFlags.pointee = .offlineUnitRenderAction_Render
            } else {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
            }
            return noErr
        }

        let count = min(available, intFrameCount)
        self.output.withUnsafeBufferPointer { ptr in
            frames.assign(from: ptr.baseAddress!.advanced(by: self.outputOffset), count: count)
        }
        outputAudioBufferList.pointee.mBuffers.mDataByteSize = UInt32(count * MemoryLayout<Float>.size)

        self.outputOffset += count
        
        let done = (self.outputOffset >= self.output.count) && !self.isSynthesizing
        
        if done {
            actionFlags.pointee = .offlineUnitRenderAction_Complete
            self.output.removeAll()
            self.outputOffset = 0
        } else {
            actionFlags.pointee = .offlineUnitRenderAction_Render
        }
        self.outputMutex.signal()

        return noErr
    }

    private func pauseUntilRenderReady(
        needFrames: Int,
        maxRecurse: Int = 200,
        baseDelayMicroseconds: UInt32 = 1000
    ) -> Bool {
        let maxDelaySeconds = Double(baseDelayMicroseconds) * Double(maxRecurse) / 1_000_000
        let checkIntervalSeconds = maxDelaySeconds / 5.0
        let startTime = Date()

        rhLog("RENDER_WAIT start needFrames=\(needFrames)")

        var ready = false
        var complete = false

        while Date().timeIntervalSince(startTime) < maxDelaySeconds {
            self.outputMutex.wait()
            let available = max(self.output.count - self.outputOffset, 0)
            let stillSynthesizing = self.isSynthesizing
            self.outputMutex.signal()

            ready = available >= needFrames
            complete = !stillSynthesizing

            if ready || complete {
                break
            }

            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(checkIntervalSeconds))
        }

        self.outputMutex.wait()
        let finalAvailable = max(self.output.count - self.outputOffset, 0)
        let finalSynthesizing = self.isSynthesizing
        self.outputMutex.signal()

        ready = finalAvailable >= needFrames
        complete = !finalSynthesizing && !ready

        let waitedMs = Int(Date().timeIntervalSince(startTime) * 1000)
        let result = ready ? "ready" : (complete ? "complete" : "timeout")
        rhLog("RENDER_WAIT end result=\(result) waitedMs=\(waitedMs) available=\(finalAvailable)")

        return ready
    }

    public override var internalRenderBlock: AUInternalRenderBlock { self.performRender }

    // MARK: - Synthesize (eSpeak-style render buffer, sentence pipeline for long text)

    public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        let requestStart = CFAbsoluteTimeGetCurrent()
        let text = speechRequest.ssmlRepresentation
        let voiceId = speechRequest.voice.identifier

        rhLog("synth request: voice=\(voiceId) text=\(text.count) chars")

        // Діагностика: зберегти сам вхідний текст, щоб побачити, яким його віддає
        // система (нотатка в режимі редагування vs збережена читаються по-різному).
        // Працює лише з увімкненою «Розширеною діагностикою».
        RHVoiceRequestCapture.record(text: text, voiceId: voiceId)

        let ssmlSnippet = String(text.prefix(200))
        rhLog("PITCH_DIAG ssmlSnippet=\(ssmlSnippet)")
        self.outputMutex.wait()
        self.isSynthesizing = true
        self.synthesisGeneration &+= 1
        let generation = self.synthesisGeneration
        self.output.removeAll()
        self.outputOffset = 0
        self.outputMutex.signal()

        rhLog("LATENCY_DIAG synthesizeSpeechRequestMs=\(Self.elapsedMs(since: requestStart)) chars=\(text.count)")

        self.synthesisQueue.async { [weak self] in
            self?.runSynthesisPipeline(
                text: text,
                voiceId: voiceId,
                requestStart: requestStart,
                generation: generation
            )
        }
    }

    private func runSynthesisPipeline(
        text: String,
        voiceId: String,
        requestStart: CFAbsoluteTime,
        generation: UInt64
    ) {
        let preprocessingStart = CFAbsoluteTimeGetCurrent()
        guard self.shouldContinueSynthesis(generation: generation) else {
            rhLog("LATENCY_DIAG pipeline cancelled beforePreprocessing")
            return
        }
        let shouldLogNumberDiag = Self.shouldLogNumberDiagnostics(for: text)
        Self.logNumberDiagnostics(label: "input-ssml", ssml: text, force: shouldLogNumberDiag)
        Self.logApostropheEncoding(label: "input-ssml", ssml: text)

        // Resolve voice profile name
        let profileName: String
        if let descriptor = Self.publishedVoiceDescriptors().first(where: { $0.identifier == voiceId }) {
            profileName = descriptor.profileName
        } else {
            profileName = RHVoiceSharedSettings.builtInVoiceCatalog.first!.profileName
            NSLog("VOICE_CATALOG_DIAG resolve=fallback requested=%@ profile=%@", voiceId, profileName)
        }

        // Extract rate/volume from SSML
        let ssmlRatePercent = Self.extractSSMLRatePercentIfPresent(from: text)
        let ssmlVolume = Self.extractSSMLVolumeIfPresent(from: text)
        let ssmlPitch = Self.extractSSMLPitch(from: text)

        // Read the accelerator/speed fresh at the moment of speaking (like builds
        // ≤157), bounded so a wedged container can never freeze the voice (task-086).
        let snapshot = self.sharedSettingsCache.snapshotRefreshingNow()
        let voiceSettings = snapshot.effectiveSettings(for: voiceId)
        let settingsMs = Self.elapsedMs(since: preprocessingStart)

        let effectiveRatePercent = ssmlRatePercent ?? 100.0
        let mappedRate = ssmlRatePercent.map(Self.mapSSMLRatePercentToEngineMultiplier)
            ?? 1.0
        let accelerator = Self.clampSpeedMultiplier(voiceSettings.speedMultiplier)
        let finalRate = Self.clampRate(mappedRate * accelerator)
        let effectiveVolume = ssmlVolume ?? 1.0
        let finalVolume = Self.clampVolume(effectiveVolume)
        let effectivePitch = Self.clampPitch(ssmlPitch ?? 1.0)
        let sentencePauseMs = Int(Self.clampSentencePause(voiceSettings.sentencePause).rounded())
        let wordGapMs = Int(Self.clampWordGap(voiceSettings.wordGap).rounded())
        let normalizedText = Self.normalizeStandaloneApostropheRequest(text)
            ?? Self.normalizeApostrophesInTextSegments(text)
        Self.logNumberDiagnostics(label: "after-apostrophe-normalize", ssml: normalizedText, force: shouldLogNumberDiag)
        Self.logApostropheEncoding(label: "after-apostrophe-normalize", ssml: normalizedText)
        let synthesisText = Self.applyTextBreaks(to: normalizedText, sentencePauseMs: sentencePauseMs, wordGapMs: wordGapMs)
        Self.logNumberDiagnostics(label: "final-engine-input", ssml: synthesisText, force: shouldLogNumberDiag)
        Self.logApostropheEncoding(label: "final-engine-input", ssml: synthesisText)

        #if DEBUG
        rhLog("synth: voice=\(profileName) ssmlRate=\(String(format: "%.1f", effectiveRatePercent))% mapped=\(String(format: "%.2f", mappedRate)) accelerator=\(String(format: "%.2f", accelerator)) final=\(String(format: "%.2f", finalRate)) vol=\(String(format: "%.2f", finalVolume)) pitch=\(String(format: "%.2f", effectivePitch)) pauseMs=\(sentencePauseMs) wordGapMs=\(wordGapMs)")
        os_log(.info, log: paramLog, "PARAMS ssmlRatePct=%.1f mappedRate=%.2f accelerator=%.2f finalRate=%.2f vol=%.2f pitch=%.2f pauseMs=%d useCustom=%d wordGapMs=%d", effectiveRatePercent, mappedRate, accelerator, finalRate, finalVolume, effectivePitch, sentencePauseMs, (accelerator != 1.0 || ssmlPitch != nil || wordGapMs > 0 || sentencePauseMs > 0) ? 1 : 0, wordGapMs)
        fputs(String(format: "PARAMS ssmlRatePct=%.1f mappedRate=%.2f accelerator=%.2f finalRate=%.2f vol=%.2f pitch=%.2f pauseMs=%d useCustom=%d wordGapMs=%d\n", effectiveRatePercent, mappedRate, accelerator, finalRate, finalVolume, effectivePitch, sentencePauseMs, (accelerator != 1.0 || ssmlPitch != nil || wordGapMs > 0 || sentencePauseMs > 0) ? 1 : 0, wordGapMs), stderr)
        #endif

        let fragments = RHVoicePipelineSplitter.pipelineFragments(from: synthesisText)
        let preprocessingMs = Self.elapsedMs(since: preprocessingStart)
        rhLog("LATENCY_DIAG prepare voice=\(profileName) chars=\(text.count) settingsMs=\(settingsMs) backgroundPreprocessingMs=\(preprocessingMs) beforeSynthesizeMs=\(Self.elapsedMs(since: requestStart))")
        rhLog("LATENCY_DIAG pipeline plan fragments=\(fragments.count) chars=\(synthesisText.count)")

        let synthStart = CFAbsoluteTimeGetCurrent()
        var totalSamples = 0
        var firstFragmentSynthMs: Int?
        var fragmentSynthMsTotal = 0

        for (index, pipelineFragment) in fragments.enumerated() {
            if !self.shouldContinueSynthesis(generation: generation) {
                rhLog("LATENCY_DIAG pipeline cancelled beforeFragment=\(index + 1)")
                break
            }
            let fragment = pipelineFragment.ssml

            let fragmentStart = CFAbsoluteTimeGetCurrent()
            var pcmBuffer = rhvoiceEngine.synthesize(
                fragment,
                voice: profileName,
                rate: finalRate,
                volume: finalVolume,
                pitch: effectivePitch
            )
            var fragmentSynthMs = Self.elapsedMs(since: fragmentStart)

            // Fallback: if SSML synthesis failed, try plain text without tags for this fragment.
            if pcmBuffer == nil && fragment.contains("<") {
                let plainText = stripSSML(fragment)
                rhLog("synth: SSML fragment failed, trying fallback: \(plainText.prefix(50))...")
                let fallbackStart = CFAbsoluteTimeGetCurrent()
                pcmBuffer = rhvoiceEngine.synthesize(
                    plainText,
                    voice: profileName,
                    rate: finalRate,
                    volume: finalVolume,
                    pitch: effectivePitch
                )
                fragmentSynthMs += Self.elapsedMs(since: fallbackStart)
            }

            fragmentSynthMsTotal += fragmentSynthMs
            if firstFragmentSynthMs == nil {
                firstFragmentSynthMs = fragmentSynthMs
            }

            guard let buffer = pcmBuffer, let floatData = buffer.floatChannelData?[0] else {
                rhLog("synth fragment FAILED index=\(index + 1)")
                rhLog("LATENCY_DIAG fragment #\(index + 1) chars=\(fragment.count) synthMs=\(fragmentSynthMs) samples=0 failed=1")
                continue
            }

            let frameCount = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: floatData, count: frameCount))
            let silence = RHVoiceSilenceAnalyzer.measure(samples: samples, sampleRate: buffer.format.sampleRate)
            let trimLeading = pipelineFragment.continuesSentence
            let trimTrailing = index + 1 < fragments.count && fragments[index + 1].continuesSentence
            let outputSamples = RHVoiceSilenceAnalyzer.trimMidSentenceSilence(
                samples: samples,
                sampleRate: buffer.format.sampleRate,
                trimLeading: trimLeading,
                trimTrailing: trimTrailing
            )
            totalSamples += outputSamples.count

            self.outputMutex.wait()
            let appendAllowed = self.isSynthesizing && self.synthesisGeneration == generation
            if appendAllowed {
                self.output.append(contentsOf: outputSamples)
            }
            self.outputMutex.signal()

            if !appendAllowed {
                rhLog("LATENCY_DIAG pipeline cancelled afterFragment=\(index + 1)")
                break
            }

            rhLog("synth fragment output index=\(index + 1) samples=\(outputSamples.count)")
            rhLog("LATENCY_DIAG fragment #\(index + 1) chars=\(fragment.count) leadingSilenceMs=\(silence.leadingSilenceMs) trailingSilenceMs=\(silence.trailingSilenceMs) trimLeading=\(trimLeading ? 1 : 0) trimTrailing=\(trimTrailing ? 1 : 0) synthMs=\(fragmentSynthMs) samples=\(outputSamples.count) rawSamples=\(samples.count)")
        }

        self.outputMutex.wait()
        if self.synthesisGeneration == generation {
            self.isSynthesizing = false
        }
        self.outputMutex.signal()

        rhLog("synth output: \(totalSamples) samples")
        rhLog("LATENCY_DIAG output voice=\(profileName) chars=\(text.count) synthMs=\(fragmentSynthMsTotal) totalMs=\(Self.elapsedMs(since: requestStart)) samples=\(totalSamples)")
        rhLog("LATENCY_DIAG pipeline fragments=\(fragments.count) firstFragmentSynthMs=\(firstFragmentSynthMs ?? 0) totalSynthMs=\(Self.elapsedMs(since: synthStart)) samples=\(totalSamples)")
    }

    private func stripSSML(_ ssml: String) -> String {
        return ssml.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private func shouldContinueSynthesis(generation: UInt64) -> Bool {
        self.outputMutex.wait()
        let shouldContinue = self.isSynthesizing && self.synthesisGeneration == generation
        self.outputMutex.signal()
        return shouldContinue
    }

    // MARK: - Cancel (exactly like eSpeak)

    public override func cancelSpeechRequest() {
        self.outputMutex.wait()
        self.isSynthesizing = false
        self.synthesisGeneration &+= 1
        self.output.removeAll()
        self.outputOffset = 0
        rhLog("cancel")
        self.outputMutex.signal()
    }

    // MARK: - Message Channel

    public override func messageChannel(for channelName: String) -> AUMessageChannel {
        final class MC: AUMessageChannel {
            var callHostBlock: CallHostBlock? { get { nil } set {} }
            func callAudioUnit(_ message: [AnyHashable : Any]) -> [AnyHashable : Any] {
                if message["initHost"] as? Bool == true {
                    let voices = UkrainianSpeechSynthesizer.publishedProviderVoices()
                    return [
                        "voiceIds": voices.map(\.identifier),
                        "voiceNames": voices.map(\.name),
                        "primaryLanguages": voices.map { $0.primaryLanguages.first ?? "uk-UA" }
                    ]
                }
                return [:]
            }
        }
        return MC()
    }

    // MARK: - SSML parsing

    private static func extractSSMLRatePercent(from ssml: String) -> Double {
        extractSSMLRatePercentIfPresent(from: ssml) ?? 100.0
    }

    private static func extractSSMLRatePercentIfPresent(from ssml: String) -> Double? {
        guard let match = try? NSRegularExpression(pattern: #"rate="([0-9]+(?:\.[0-9]+)?)%""#)
            .firstMatch(in: ssml, range: NSRange(ssml.startIndex..., in: ssml)),
              let range = Range(match.range(at: 1), in: ssml),
              let pct = Double(ssml[range]) else { return nil }
        return max(0.0, pct)
    }

    private static func mapSSMLRatePercentToEngineMultiplier(_ percent: Double) -> Double {
        let normalized = max(0.0, percent) / 100.0
        return min(max(normalized, 0.5), 3.0)
    }

    private static func clampRate(_ value: Double) -> Double {
        min(max(value, 0.1), 20.0)
    }

    private static func clampSpeedMultiplier(_ value: Double) -> Double {
        min(max(value, 0.8), 1.6)
    }

    private static func elapsedMs(since start: CFAbsoluteTime) -> Int {
        Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())
    }

    private static func clampVolume(_ value: Double) -> Double {
        min(max(value, 0.0), 2.0)
    }

    private static func clampPitch(_ value: Double) -> Double {
        min(max(value, 0.5), 2.0)
    }

    private static func extractSSMLPitch(from ssml: String) -> Double? {
        guard let match = try? NSRegularExpression(pattern: #"pitch\s*=\s*"([^"]+)""#, options: [.caseInsensitive])
            .firstMatch(in: ssml, range: NSRange(ssml.startIndex..., in: ssml)),
              let range = Range(match.range(at: 1), in: ssml) else { return nil }

        let rawPitch = ssml[range].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch rawPitch {
        case "x-low":
            return 0.5
        case "low":
            return 0.75
        case "medium", "default":
            return 1.0
        case "high":
            return 1.25
        case "x-high":
            return 1.5
        default:
            break
        }

        if rawPitch.hasSuffix("%") {
            let numeric = rawPitch.dropLast()
            if let percent = Double(numeric) {
                if numeric.first == "+" || numeric.first == "-" {
                    return 1.0 + (percent / 100.0)
                }
                return percent / 100.0
            }
        }

        if rawPitch.hasSuffix("st"),
           let semitones = Double(rawPitch.dropLast(2)) {
            return pow(2.0, semitones / 12.0)
        }

        if rawPitch.hasSuffix("hz") {
            return nil
        }

        return nil
    }

    private static func clampSentencePause(_ value: Double) -> Double {
        min(max(value, 0.0), 2_000.0)
    }

    private static func clampWordGap(_ value: Double) -> Double {
        min(max(value, 0.0), 300.0)
    }

    private static func normalizeApostrophesInTextSegments(_ ssml: String) -> String {
        RHVoiceApostropheNormalizer.normalizeInTextSegments(
            ssml,
            datesAsWords: rhDatesAsWordsEnabled(),
            timeAsWords: rhTimeAsWordsEnabled(),
            abbreviationsAsWords: rhAbbreviationsAsWordsEnabled(),
            abbreviationDictionaryEnabled: rhAbbreviationDictionaryEnabled(),
            phoneProcessing: rhPhoneNumberProcessingEnabled(),
            phoneReadingMode: rhPhoneNumberReadingMode()
        )
    }

    private static func normalizeStandaloneApostropheRequest(_ ssml: String) -> String? {
        RHVoiceApostropheNormalizer.normalizeStandaloneApostropheRequest(ssml)
    }

    private static func normalizeApostrophes(_ text: String) -> String {
        RHVoiceApostropheNormalizer.normalizeText(text)
    }

    private static func logApostropheEncoding(label: String, ssml: String) {
        #if DEBUG
        let textSegments = extractTextSegments(from: ssml)
        let matches = textSegments.flatMap { apostropheDiagnostics(in: $0) }

        guard !matches.isEmpty else {
            apostropheDiagLog("APOSTROPHE_DIAG \(label): no apostrophe-like scalars in text segments")
            return
        }

        for (index, match) in matches.enumerated() {
            apostropheDiagLog("APOSTROPHE_DIAG \(label)#\(index + 1): \(match)")
        }
        #endif
    }

    private static func shouldLogNumberDiagnostics(for ssml: String) -> Bool {
        ssml.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
    }

    private static func logNumberDiagnostics(label: String, ssml: String, force: Bool) {
        if !didLogNumberDiagActiveBuild {
            didLogNumberDiagActiveBuild = true
            let info = Bundle.main.infoDictionary ?? [:]
            let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
            let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
            let build = info["CFBundleVersion"] as? String ?? "unknown"
            numberDiag("active-build bundle=\(bundleId) version=\(version) build=\(build)")
        }

        let textSegments = extractTextSegments(from: ssml)
        let windows = textSegments.flatMap { numberDiagnosticWindows(in: $0) }
        guard force || !windows.isEmpty else { return }

        let preview = diagnosticPreview(ssml)
        let previewScalars = diagnosticScalars(for: preview)
        numberDiag("\(label): chars=\(ssml.count) textPreview=\"\(preview)\" scalars=[\(previewScalars)]")

        if windows.isEmpty {
            numberDiag("\(label): no digit windows in text segments")
            return
        }

        for (index, window) in windows.prefix(8).enumerated() {
            numberDiag("\(label)#\(index + 1): token=\"\(window.token)\" window=\"\(window.window)\" scalars=[\(window.scalars)]")
        }
    }

    private static func numberDiag(_ message: String) {
        os_log(.info, log: numberDiagLog, "NUMBER_DIAG %{public}@", message as NSString)
        fputs("NUMBER_DIAG \(message)\n", stderr)
        if rhExtendedDiagnosticsEnabled() {
            "NUMBER_DIAG \(message)".withCString { RHVoiceDebugLogString($0) }
        }
    }

    private struct NumberDiagnosticWindow {
        let token: String
        let window: String
        let scalars: String
    }

    private static func numberDiagnosticWindows(in text: String) -> [NumberDiagnosticWindow] {
        let scalars = Array(text.unicodeScalars)
        var results: [NumberDiagnosticWindow] = []
        var index = scalars.startIndex

        while index < scalars.endIndex {
            guard CharacterSet.decimalDigits.contains(scalars[index]) else {
                index += 1
                continue
            }

            let tokenStart = index
            var tokenEnd = index + 1
            while tokenEnd < scalars.endIndex, isNumberDiagnosticTokenScalar(scalars[tokenEnd]) {
                tokenEnd += 1
            }

            let windowStart = max(scalars.startIndex, tokenStart - 16)
            let windowEnd = min(scalars.endIndex, tokenEnd + 16)
            let token = diagnosticPreview(String(String.UnicodeScalarView(scalars[tokenStart..<tokenEnd])), limit: 64)
            let window = diagnosticPreview(String(String.UnicodeScalarView(scalars[windowStart..<windowEnd])), limit: 160)
            let scalarCodes = scalars[windowStart..<windowEnd]
                .map { String(format: "U+%04X", $0.value) }
                .joined(separator: " ")
            results.append(NumberDiagnosticWindow(token: token, window: window, scalars: scalarCodes))
            index = tokenEnd
        }

        return results
    }

    private static func isNumberDiagnosticTokenScalar(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.decimalDigits.contains(scalar)
            || scalar == ","
            || scalar == "."
            || scalar == "/"
            || CharacterSet.whitespaces.contains(scalar)
    }

    private static func diagnosticPreview(_ text: String, limit: Int = 320) -> String {
        var preview = String(text.prefix(limit))
        if text.count > limit {
            preview += "..."
        }
        return preview
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func diagnosticScalars(for text: String, limit: Int = 120) -> String {
        let scalars = Array(text.unicodeScalars.prefix(limit))
        var codes = scalars.map { String(format: "U+%04X", $0.value) }
        if text.unicodeScalars.count > limit {
            codes.append("...")
        }
        return codes.joined(separator: " ")
    }

    private static func extractTextSegments(from ssml: String) -> [String] {
        var segments: [String] = []
        var textSegment = ""
        var insideTag = false

        for character in ssml {
            if insideTag {
                if character == ">" {
                    insideTag = false
                }
            } else if character == "<" {
                if !textSegment.isEmpty {
                    segments.append(textSegment)
                    textSegment.removeAll(keepingCapacity: true)
                }
                insideTag = true
            } else {
                textSegment.append(character)
            }
        }

        if !textSegment.isEmpty {
            segments.append(textSegment)
        }
        return segments
    }

    private static func apostropheDiagnostics(in text: String) -> [String] {
        let scalars = Array(text.unicodeScalars)
        var results: [String] = []

        for index in scalars.indices where isApostropheLikeScalar(scalars[index]) {
            let wordRange = diagnosticWordRange(around: index, in: scalars)
            let wordScalars = Array(scalars[wordRange])
            let word = String(String.UnicodeScalarView(wordScalars))
            let codepoints = wordScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
            let utf8Bytes = word.utf8.map { String(format: "%02X", $0) }.joined(separator: " ")
            let apostrophe = String(format: "U+%04X", scalars[index].value)
            results.append("apostrophe=\(apostrophe) word=\(word) codepoints=[\(codepoints)] utf8=[\(utf8Bytes)]")
        }

        return results
    }

    private static func isApostropheLikeScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0027, 0x0060, 0x00B4, 0x02BC, 0x055A, 0x2018, 0x2019, 0x2032, 0xA78B, 0xA78C, 0xFF07:
            return true
        default:
            return false
        }
    }

    private static func diagnosticWordRange(around index: Int, in scalars: [UnicodeScalar]) -> Range<Int> {
        var start = index
        var end = index + 1

        while start > scalars.startIndex, isDiagnosticWordScalar(scalars[start - 1]) {
            start -= 1
        }

        while end < scalars.endIndex, isDiagnosticWordScalar(scalars[end]) {
            end += 1
        }

        return start..<end
    }

    private static func isDiagnosticWordScalar(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.letters.contains(scalar)
            || CharacterSet.decimalDigits.contains(scalar)
            || isApostropheLikeScalar(scalar)
    }

    private static func applyTextBreaks(to ssml: String, sentencePauseMs: Int, wordGapMs: Int) -> String {
        guard sentencePauseMs > 0 || wordGapMs > 0 else { return ssml }

        var output = ""
        var textSegment = ""
        var tagSegment = ""
        var insideTag = false

        for character in ssml {
            if insideTag {
                tagSegment.append(character)
                if character == ">" {
                    output += transformTextSegment(textSegment, sentencePauseMs: sentencePauseMs, wordGapMs: wordGapMs)
                    textSegment.removeAll(keepingCapacity: true)
                    output += tagSegment
                    tagSegment.removeAll(keepingCapacity: true)
                    insideTag = false
                }
            } else if character == "<" {
                insideTag = true
                tagSegment.append(character)
            } else {
                textSegment.append(character)
            }
        }

        if insideTag {
            output += textSegment + tagSegment
        } else {
            output += transformTextSegment(textSegment, sentencePauseMs: sentencePauseMs, wordGapMs: wordGapMs)
        }

        if output.range(of: #"<\s*speak\b"#, options: .regularExpression) != nil {
            return output
        }
        return "<speak>\(output)</speak>"
    }

    private static func transformTextSegment(_ text: String, sentencePauseMs: Int, wordGapMs: Int) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return text }

        var output = ""
        for index in characters.indices {
            let character = characters[index]
            output.append(character)

            if sentencePauseMs > 0 && isSentencePunctuation(character) && !isDecimalSeparator(characters, at: index) {
                output += "<break time='\(sentencePauseMs)ms'/>"
            }

            if wordGapMs > 0 && isWordCharacter(character) {
                let nextIndex = index + 1
                if nextIndex < characters.count, isWhitespace(characters[nextIndex]), nextWordStarts(afterWhitespaceFrom: nextIndex, in: characters) {
                    output += "<break time='\(wordGapMs)ms'/>"
                }
            }
        }
        return output
    }

    private static func nextWordStarts(afterWhitespaceFrom index: Int, in characters: [Character]) -> Bool {
        var cursor = index
        while cursor < characters.count, isWhitespace(characters[cursor]) {
            cursor += 1
        }
        return cursor < characters.count && isWordCharacter(characters[cursor])
    }

    private static func isSentencePunctuation(_ character: Character) -> Bool {
        character == "." || character == "," || character == "!" || character == "?"
    }

    private static func isDecimalSeparator(_ characters: [Character], at index: Int) -> Bool {
        guard characters[index] == "." || characters[index] == "," else { return false }
        let previous = index > 0 ? characters[index - 1] : nil
        let next = index + 1 < characters.count ? characters[index + 1] : nil
        return previous?.isNumber == true && next?.isNumber == true
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
    }

    private static func extractSSMLVolume(from ssml: String) -> Double {
        extractSSMLVolumeIfPresent(from: ssml) ?? 1.0
    }

    private static func extractSSMLVolumeIfPresent(from ssml: String) -> Double? {
        guard let match = try? NSRegularExpression(pattern: #"volume="([+-]?[0-9]+(?:\.[0-9]+)?)dB""#)
            .firstMatch(in: ssml, range: NSRange(ssml.startIndex..., in: ssml)),
              let range = Range(match.range(at: 1), in: ssml),
              let db = Double(ssml[range]) else { return nil }
        return max(0.1, min(2.0, pow(10.0, db / 20.0)))
    }
}
