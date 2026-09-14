//
//  ExportReadinessTests.swift
//  AppTapeTests
//

import Testing
@testable import AppTape

/// The one decision that refuses an Export (ADR-0012, ADR-0015, ADR-0034, ADR-0041, ADR-0042).
///
/// Five ordered rules that used to live in two places with three wordings and two units, and in
/// neither place could be reached without a window. Every input here is a scalar or a bare
/// `SourceFormat`, so the whole matrix is exercised with no `Recording`, no file and no main actor —
/// which is also why the suite carries no `@MainActor`, like `QualityPresetTests` and `DiskSpaceTests`.
struct ExportReadinessTests {
    private let stereo48 = SourceFormat(sampleRate: 48_000, channelCount: 2, bitsPerChannel: 32)
    /// The source ADR-0041 needed a doctored Library to photograph: the three AAC rungs refuse it.
    private let hiRes96 = SourceFormat(sampleRate: 96_000, channelCount: 2, bitsPerChannel: 32)

    /// An ordinary settled Recording with a Trim in it, at a rung that can encode it. Every rule
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
        #expect(evaluate().refusal == nil)
    }

    // MARK: - Each rule, and the sentence it prints (ADR-0042)

    @Test func eachRuleRefusesWithItsOwnSentence() {
        #expect(evaluate(isOpenable: false).refusal == .unopenable)
        #expect(ExportReadiness.Reason.unopenable.sentence == "AppTape can't decode this file.")

        #expect(evaluate(isCapturing: true).refusal == .stillCapturing)
        #expect(ExportReadiness.Reason.stillCapturing.sentence == "This Recording is still capturing.")

        #expect(evaluate(frames: 0).refusal == .emptyTrim)
        #expect(ExportReadiness.Reason.emptyTrim.sentence == "Nothing in the Trim to export.")

        #expect(evaluate(format: hiRes96).refusal?.sentence == "This quality can't encode this file.")

        #expect(evaluate(isExporting: true).refusal == .alreadyRunning)
        #expect(ExportReadiness.Reason.alreadyRunning.sentence == "An Export is already running.")
    }

    /// A negative frame count is the same refusal as zero. `trimmedFrameRange` cannot produce one
    /// today, but the rule is `<= 0` rather than `== 0` so that a future caller's arithmetic cannot
    /// slip an Export of nothing past the gate.
    @Test func aNegativeFrameCountIsRefusedLikeAnEmptyOne() {
        #expect(evaluate(frames: -1).refusal == .emptyTrim)
    }

    // MARK: - The order, which is the half that was never written down

    @Test func theOrderIsUnopenableCapturingEmptyUnencodableRunning() {
        // Each adjacent pair, both true: the earlier rule wins.
        #expect(evaluate(isOpenable: false, isCapturing: true).refusal == .unopenable)
        #expect(evaluate(isCapturing: true, frames: 0).refusal == .stillCapturing)
        #expect(evaluate(frames: 0, format: hiRes96).refusal == .emptyTrim)
        #expect(evaluate(format: hiRes96, isExporting: true).refusal?.sentence
                == "This quality can't encode this file.")

        // Everything wrong at once still reads as the first rule.
        #expect(evaluate(isOpenable: false, isCapturing: true, frames: 0,
                         format: hiRes96, isExporting: true).refusal == .unopenable)
    }

    // MARK: - The two rules that used to be accidents

    /// An adopted file with no audio in it. It was refused before this module existed, but only
    /// because `Trim(duration: 0).length` is 0 — an invariant three files away, asserted nowhere.
    /// Here it is the rule itself.
    @Test func anAdoptedFileWithNoAudioIsRefusedAsAnEmptyTrim() {
        #expect(evaluate(frames: 0).refusal == .emptyTrim)
    }

    /// A file the decoder cannot open (ADR-0015). It, too, was refused only as arithmetic: an
    /// unopenable Recording reads back as zero frames, so it fell into the Trim rule and was told the
    /// wrong thing for the right reason. Stated, it wins first — and note the frame count here is
    /// positive, which is what the old arrangement could not survive.
    @Test func aFileThatCannotBeDecodedIsRefusedBeforeAnythingElseIsAsked() {
        #expect(evaluate(isOpenable: false, frames: 48_000).refusal == .unopenable)
    }

    /// The divergence this module exists to close. The dock measured `trimmedDuration` in seconds and
    /// the coordinator measured `trimmedFrameRange` in frames, and a Recording whose Trim is `isFixed`
    /// can report a positive length in seconds with zero frames behind it — so the dock offered a
    /// button whose click produced a failure telling. Frames decide.
    @Test func aTrimWithNoFramesIsRefusedHoweverManySecondsItClaims() {
        #expect(evaluate(frames: 0).refusal == .emptyTrim)
        // One frame is an Export. The rule is "nothing in the Trim", not "not enough in the Trim" —
        // ADR-0015 keeps a sub-0.2 s adopted file exportable at its whole length.
        #expect(evaluate(frames: 1) == .ready)
    }

    // MARK: - The specific reason, carried but not printed (ADR-0041 / ADR-0042)

    @Test func anUnencodableReasonCarriesTheRungsOwnWordsAndPrintsTheGenericLine() {
        let refusal = evaluate(format: hiRes96).refusal
        guard case .unencodable(let detail) = refusal else {
            Issue.record("expected an unencodable refusal, got \(String(describing: refusal))")
            return
        }
        // The rung's sentence, whole — this is what ADR-0041 prints beside the rung at full strength.
        #expect(detail.contains("48 kHz"))
        #expect(detail.contains("96 kHz"))
        // And the dock's, which names the situation only: ADR-0042's trade, asserted.
        #expect(refusal?.sentence == "This quality can't encode this file.")
        #expect(refusal?.sentence.contains("96 kHz") == false)
    }

    /// Master/ALAC is the universal rung (ADR-0015), so the same source that refuses three rungs is
    /// ready on the fourth. The refusal is about the *effective preset*, never about the file alone.
    @Test func theSameSourceIsReadyOnARungThatCanEncodeIt() {
        #expect(evaluate(preset: .master, format: hiRes96) == .ready)
        #expect(evaluate(preset: .standard, format: hiRes96).refusal?.sentence
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
