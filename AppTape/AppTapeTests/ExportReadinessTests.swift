import Testing
@testable import AppTape

/// The one decision that refuses an Export.
struct ExportReadinessTests {
    private let stereo48 = SourceFormat(sampleRate: 48_000, channelCount: 2, bitsPerChannel: 32)
    /// The source needed a doctored Library to photograph: the three AAC preset rows refuse it.
    private let hiRes96 = SourceFormat(sampleRate: 96_000, channelCount: 2, bitsPerChannel: 32)

    /// An ordinary settled Recording with a Trim in it, at a preset row that can encode it. Every rule
    /// below flips exactly one of these.
    private func evaluate(isOpenable: Bool = true,
                          isCapturing: Bool = false,
                          frames: Int64 = 48_000,
                          preset: QualityPreset = .high,
                          format: SourceFormat? = nil,
                          isExporting: Bool = false) -> ExportReadiness {
        .evaluate(isOpenable: isOpenable, isCapturing: isCapturing, trimmedFrameCount: frames,
                  preset: preset, format: format ?? stereo48, isExporting: isExporting)
    }

    @Test func anOpenableSettledIdleRecordingWithFramesIsReady() {
        #expect(evaluate() == .ready)
        #expect(evaluate().blocker == nil)
    }

    // MARK: - Each rule, and the sentence it prints

    @Test func eachRuleRefusesWithItsOwnSentence() {
        #expect(evaluate(isOpenable: false).blocker == .unopenable)
        #expect(ExportReadiness.Reason.unopenable.sentence == "AppTape can't decode this file.")

        #expect(evaluate(isCapturing: true).blocker == .stillCapturing)
        #expect(ExportReadiness.Reason.stillCapturing.sentence == "This Recording is still capturing.")

        #expect(evaluate(frames: 0).blocker == .emptyTrim)
        #expect(ExportReadiness.Reason.emptyTrim.sentence == "Nothing in the Trim to export.")

        #expect(evaluate(format: hiRes96).blocker?.sentence == "This quality can't encode this file.")

        #expect(evaluate(isExporting: true).blocker == .alreadyRunning)
        #expect(ExportReadiness.Reason.alreadyRunning.sentence == "An Export is already running.")
    }

    /// A negative frame count is the same blocker as zero.
    @Test func aNegativeFrameCountIsRefusedLikeAnEmptyOne() {
        #expect(evaluate(frames: -1).blocker == .emptyTrim)
    }

    // MARK: - The order, which is the half that was never written down

    @Test func theOrderIsUnopenableCapturingEmptyUnencodableRunning() {
        // Each adjacent pair, both true: the earlier rule wins.
        #expect(evaluate(isOpenable: false, isCapturing: true).blocker == .unopenable)
        #expect(evaluate(isCapturing: true, frames: 0).blocker == .stillCapturing)
        #expect(evaluate(frames: 0, format: hiRes96).blocker == .emptyTrim)
        #expect(evaluate(format: hiRes96, isExporting: true).blocker?.sentence
                == "This quality can't encode this file.")

        // Everything wrong at once still reads as the first rule.
        #expect(evaluate(isOpenable: false, isCapturing: true, frames: 0,
                         format: hiRes96, isExporting: true).blocker == .unopenable)
    }

    // MARK: - The two rules that used to be accidents

    /// An adopted file with no audio in it.
    @Test func anAdoptedFileWithNoAudioIsRefusedAsAnEmptyTrim() {
        #expect(evaluate(frames: 0).blocker == .emptyTrim)
    }

    /// A file the decoder cannot open.
    @Test func aFileThatCannotBeDecodedIsRefusedBeforeAnythingElseIsAsked() {
        #expect(evaluate(isOpenable: false, frames: 48_000).blocker == .unopenable)
    }

    /// The divergence this module exists to close.
    @Test func aTrimWithNoFramesIsRefusedHoweverManySecondsItClaims() {
        #expect(evaluate(frames: 0).blocker == .emptyTrim)
        // One frame is an Export.
        #expect(evaluate(frames: 1) == .ready)
    }

    // MARK: - The specific reason, carried but not printed (/)

    @Test func anUnencodableReasonCarriesTheRungsOwnWordsAndPrintsTheGenericLine() {
        let blocker = evaluate(format: hiRes96).blocker
        guard case .unencodable(let detail) = blocker else {
            Issue.record("expected an unencodable blocker, got \(String(describing: blocker))")
            return
        }
        // The preset row's sentence, whole — this is what prints beside the preset row at full strength.
        #expect(detail.contains("48 kHz"))
        #expect(detail.contains("96 kHz"))
        // And the dock's, which names the situation only: the trade, asserted.
        #expect(blocker?.sentence == "This quality can't encode this file.")
        #expect(blocker?.sentence.contains("96 kHz") == false)
    }

    /// Master/ALAC is the universal preset row, so the same source that refuses three preset rows is
    /// ready on the fourth. The blocker is about the *effective preset*, never about the file alone.
    @Test func theSameSourceIsReadyOnARungThatCanEncodeIt() {
        #expect(evaluate(preset: .master, format: hiRes96) == .ready)
        #expect(evaluate(preset: .standard, format: hiRes96).blocker?.sentence
                == "This quality can't encode this file.")
    }

    // MARK: - The glyph

    @Test func onlyStillCapturingUsesTheRecordGlyph() {
        #expect(ExportReadiness.Reason.stillCapturing.symbolName == "record.circle")
        for reason: ExportReadiness.Reason in [.unopenable, .emptyTrim,
                                               .unencodable("any"), .alreadyRunning] {
            #expect(reason.symbolName == "square.and.arrow.up")
        }
    }
}
