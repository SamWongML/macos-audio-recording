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

    // MARK: - Faithful-or-refuse encodability (ADR-0015)

    @Test func aCapturedStereo48MasterEncodesOnEveryRung() {
        // The plain path: 48 kHz stereo is the captured master, and every rung takes it.
        for preset in QualityPreset.allCases {
            #expect(preset.encodability(for: stereo48) == .available)
        }
    }

    @Test func aHiResSourceRefusesTheThreeAACRungsButNotMaster() {
        let hiRes = SourceFormat(sampleRate: 96_000, channelCount: 2, bitsPerChannel: 24)
        #expect(QualityPreset.master.encodability(for: hiRes) == .available)   // ALAC takes any rate
        for preset in [QualityPreset.high, .standard, .compact] {
            let encodability = preset.encodability(for: hiRes)
            #expect(!encodability.isAvailable)
            #expect(encodability.reason?.contains("48 kHz") == true)
            #expect(encodability.reason?.contains("96 kHz") == true)   // names the source's real rate
        }
    }

    @Test func aMonoSourceRefusesOnlyCompact() {
        // HE-AAC takes even channel counts only, so mono disables Compact — but AAC-LC and ALAC take it.
        let mono = SourceFormat(sampleRate: 44_100, channelCount: 1, bitsPerChannel: 16)
        #expect(QualityPreset.master.encodability(for: mono) == .available)
        #expect(QualityPreset.high.encodability(for: mono) == .available)
        #expect(QualityPreset.standard.encodability(for: mono) == .available)
        let compact = QualityPreset.compact.encodability(for: mono)
        #expect(!compact.isAvailable)
        #expect(compact.reason?.contains("even") == true)
    }

    @Test func anOddMultichannelSourceRefusesOnlyCompact() {
        // 3 channels: odd, so Compact refuses; AAC-LC (≤ 8 ch) and ALAC still take it.
        let threeCh = SourceFormat(sampleRate: 48_000, channelCount: 3, bitsPerChannel: 24)
        #expect(QualityPreset.high.encodability(for: threeCh) == .available)
        #expect(QualityPreset.compact.encodability(for: threeCh).reason?.contains("3 channels") == true)

        // 6 channels (5.1): even and ≤ 8, so every rung takes it.
        let fiveOne = SourceFormat(sampleRate: 48_000, channelCount: 6, bitsPerChannel: 24)
        for preset in QualityPreset.allCases {
            #expect(preset.encodability(for: fiveOne) == .available)
        }
    }

    @Test func masterIsTheAlwaysWorksEscapeHatchAcrossExoticRatesAndChannels() {
        // The escape hatch: any rate, up to 8 channels — Master takes it where the AAC rungs won't.
        for rate in [44_100.0, 48_000, 88_200, 96_000, 192_000] {
            for channels in 1...8 {
                let format = SourceFormat(sampleRate: rate, channelCount: channels, bitsPerChannel: 24)
                #expect(QualityPreset.master.encodability(for: format) == .available)
            }
        }
        // Beyond 8 channels even Master refuses — the one file with no faithful rung.
        let nineCh = SourceFormat(sampleRate: 48_000, channelCount: 9, bitsPerChannel: 24)
        #expect(!QualityPreset.master.encodability(for: nineCh).isAvailable)
    }

    @Test func aPickUpdatesTheStickyWhenItFitsButIsADisplayOverWhenItDoesnt() {
        let hiRes = SourceFormat(sampleRate: 96_000, channelCount: 2, bitsPerChannel: 24)

        // The sticky (High) fits a plain stereo-48 source: picking Standard updates the sticky (issue #9).
        #expect(QualityPreset.PresetPick.resolve(picking: .standard, sticky: .high, format: stereo48)
                == .setSticky(.standard))

        // The sticky (High) can't encode a 96 kHz source: picking Master is a per-file display-over
        // that leaves the sticky untouched (ADR-0015).
        #expect(QualityPreset.PresetPick.resolve(picking: .master, sticky: .high, format: hiRes)
                == .displayOver(.master))

        // A rung the source itself can't encode is ignored, whatever the sticky is.
        #expect(QualityPreset.PresetPick.resolve(picking: .high, sticky: .high, format: hiRes)
                == .ignore)
    }

    @Test func theSubtitleNamesTheCodecRateAndChannels() {
        #expect(QualityPreset.high.subtitle(for: stereo48) == "AAC 256 kbps · 48 kHz stereo")
        #expect(QualityPreset.master.subtitle(for: stereo48) == "24-bit ALAC · 48 kHz stereo")

        let cdMono = SourceFormat(sampleRate: 44_100, channelCount: 1, bitsPerChannel: 16)
        #expect(QualityPreset.compact.subtitle(for: cdMono) == "HE-AAC 64 kbps · 44.1 kHz mono")
    }
}
