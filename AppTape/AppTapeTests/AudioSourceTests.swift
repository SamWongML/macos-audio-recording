//
//  AudioSourceTests.swift
//  AppTapeTests
//

import Testing
@testable import AppTape

/// Source resolution maps raw HAL processes up onto the visible app (ADR-0001, issue #6):
/// the prefix rule for helper bundles, the localized-name rule for WebKit's GPU process.
struct AudioSourceTests {
    private let chrome = RunningApp(bundleID: "com.google.Chrome", name: "Google Chrome")
    private let safari = RunningApp(bundleID: "com.apple.Safari", name: "Safari")

    @Test func helperBundleMapsByPrefix() {
        let helper = AudioProcess(id: 10, pid: 100, bundleID: "com.google.Chrome.helper",
                                  isRunningOutput: true, appName: nil)
        #expect(SourceResolution.owningBundleID(of: helper, among: [chrome, safari]) == "com.google.Chrome")
    }

    @Test func webkitGPUMapsByLocalizedName() {
        // WebKit's GPU process has a bundle ID that names no app; only its localized
        // name ("Safari Graphics and Media") threads back to Safari.
        let gpu = AudioProcess(id: 20, pid: 200, bundleID: "com.apple.WebKit.GPU",
                               isRunningOutput: true, appName: "Safari Graphics and Media")
        #expect(SourceResolution.owningBundleID(of: gpu, among: [chrome, safari]) == "com.apple.Safari")
    }

    @Test func webkitGPUWithNoNameMapsToNothing() {
        let gpu = AudioProcess(id: 20, pid: 200, bundleID: "com.apple.WebKit.GPU",
                               isRunningOutput: true, appName: nil)
        #expect(SourceResolution.owningBundleID(of: gpu, among: [safari]) == nil)
    }

    @Test func longestPrefixWins() {
        let short = RunningApp(bundleID: "com.google", name: "Google")
        let helper = AudioProcess(id: 10, pid: 100, bundleID: "com.google.Chrome.helper",
                                  isRunningOutput: true, appName: nil)
        #expect(SourceResolution.owningBundleID(of: helper, among: [short, chrome]) == "com.google.Chrome")
    }

    @Test func unownedProcessMapsToNothing() {
        let stray = AudioProcess(id: 30, pid: 300, bundleID: "com.unknown.thing",
                                 isRunningOutput: true, appName: nil)
        #expect(SourceResolution.owningBundleID(of: stray, among: [chrome, safari]) == nil)
    }

    @Test func sourceFansOutToItsProcessObjectIDs() {
        let audioService = AudioProcess(id: 11, pid: 101, bundleID: "com.google.Chrome.helper",
                                        isRunningOutput: true, appName: nil)
        let gpuHelper = AudioProcess(id: 12, pid: 102, bundleID: "com.google.Chrome.helper.Renderer",
                                     isRunningOutput: false, appName: nil)
        let sources = SourceResolution.sources(from: [audioService, gpuHelper], apps: [chrome, safari])

        let chromeSource = try! #require(sources.first { $0.bundleID == "com.google.Chrome" })
        #expect(chromeSource.isPlaying)   // one of its processes is running output
        #expect(Set(chromeSource.processObjectIDs) == [11, 12])

        let safariSource = try! #require(sources.first { $0.bundleID == "com.apple.Safari" })
        #expect(safariSource.isPlaying == false)
        #expect(safariSource.processObjectIDs.isEmpty)   // running, but has not touched Core Audio
    }

    @Test func playingSourcesSortFirstThenAlphabetical() {
        let zulu = RunningApp(bundleID: "com.z.App", name: "Zulu")
        let alpha = RunningApp(bundleID: "com.a.App", name: "Alpha")
        let zuluAudio = AudioProcess(id: 40, pid: 400, bundleID: "com.z.App",
                                     isRunningOutput: true, appName: nil)
        let sources = SourceResolution.sources(from: [zuluAudio], apps: [alpha, zulu, chrome])
        // Zulu is playing, so it leads; the rest fall alphabetical.
        #expect(sources.map(\.name) == ["Zulu", "Alpha", "Google Chrome"])
    }
}
