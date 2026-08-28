//
//  QualityPresetTests.swift
//  AppTapeTests
//

import Testing
import Foundation
@testable import AppTape

/// The four Quality Presets and the size-estimate math (issue #9, ADR-0005, ADR-0012). These pin
/// the two properties the acceptance criteria call out: the estimate is `bitrate × duration × 1.02`
/// to three significant figures, and it is **invariant to Loudness and Gain** — a property that
/// holds here by construction, because neither is an input the estimate can take.
struct QualityPresetTests {
    private let stereo48 = SourceFormat(sampleRate: 48_000, channelCount: 2, bitsPerChannel: 32)

    @Test func thereAreExactlyFourPresetsAndHighIsDefault() {
        #expect(QualityPreset.allCases == [.master, .high, .standard, .compact])
        #expect(QualityPreset.defaultPreset == .high)
    }

    @Test func lossyRungsAreTheirTargetBitrateFlatAcrossSampleRates() {
        #expect(QualityPreset.high.targetBitrate == 256_000)
        #expect(QualityPreset.standard.targetBitrate == 128_000)
        #expect(QualityPreset.compact.targetBitrate == 64_000)
        #expect(QualityPreset.master.targetBitrate == nil)

        // A lossy target does not move with the source rate — that is what a target bitrate means.
        let hiRes = SourceFormat(sampleRate: 96_000, channelCount: 2, bitsPerChannel: 32)
        #expect(QualityPreset.high.estimatedBitsPerSecond(for: hiRes)
                == QualityPreset.high.estimatedBitsPerSecond(for: stereo48))
    }

    @Test func masterQualityEstimatesAt46PercentOfTheFloatMaster() {
        // ADR-0005: the ALAC rung is ~633 MB/hour at 48 kHz stereo Float32 (46% of the master).
        let bps = QualityPreset.master.estimatedBitsPerSecond(for: stereo48)
        let mbPerHour = bps / 8 * 3600 / 1_000_000
        #expect(abs(mbPerHour - 633) < 5)

        // It scales with the source's real rate and channels, unlike the lossy targets.
        let hiRes = SourceFormat(sampleRate: 96_000, channelCount: 2, bitsPerChannel: 32)
        #expect(QualityPreset.master.estimatedBitsPerSecond(for: hiRes)
                == 2 * QualityPreset.master.estimatedBitsPerSecond(for: stereo48))
    }

    @Test func theEstimateIsBitrateTimesDurationTimesOverhead() {
        let duration = 120.0
        let expected = QualityPreset.high.estimatedBitsPerSecond(for: stereo48) * duration * 1.02 / 8
        #expect(ExportSizeEstimate.bytes(preset: .high, format: stereo48, duration: duration) == expected)
    }

    @Test func aZeroOrNonFiniteDurationEstimatesZero() {
        #expect(ExportSizeEstimate.bytes(preset: .high, format: stereo48, duration: 0) == 0)
        #expect(ExportSizeEstimate.bytes(preset: .high, format: stereo48, duration: -5) == 0)
        #expect(ExportSizeEstimate.bytes(preset: .high, format: stereo48, duration: .nan) == 0)
    }

    @Test func theTextIsThreeSignificantFiguresWithTheApproximatelySign() {
        // AAC 256 for 6 min 30 s ≈ 256000 × 390 × 1.02 / 8 = 12,730,000-ish bytes → 12.7 MB.
        let text = ExportSizeEstimate.text(preset: .high, format: stereo48, duration: 390)
        #expect(text.hasPrefix("≈ "))
        #expect(text.hasSuffix(" MB"))
        #expect(text == "≈ 12.7 MB")
    }

    @Test func largeEstimatesReadInGigabytes() {
        // Master quality for ~3 hours is over a gigabyte (ADR-0009's amber-Runway Recording).
        let text = ExportSizeEstimate.sizeText(bytes: 1_900_000_000)
        #expect(text == "1.90 GB")
    }

    @Test func threeSignificantFiguresKeepsTrailingZeros() {
        #expect(ExportSizeEstimate.sizeText(bytes: 500_000) == "0.500 MB")
        #expect(ExportSizeEstimate.sizeText(bytes: 5_000_000) == "5.00 MB")
        #expect(ExportSizeEstimate.sizeText(bytes: 123_000_000) == "123 MB")
    }

    @Test func theSubtitleNamesTheCodecRateAndChannels() {
        #expect(QualityPreset.high.subtitle(for: stereo48) == "AAC 256 kbps · 48 kHz stereo")
        #expect(QualityPreset.master.subtitle(for: stereo48) == "24-bit ALAC · 48 kHz stereo")

        let cdMono = SourceFormat(sampleRate: 44_100, channelCount: 1, bitsPerChannel: 16)
        #expect(QualityPreset.compact.subtitle(for: cdMono) == "HE-AAC 64 kbps · 44.1 kHz mono")
    }
}
