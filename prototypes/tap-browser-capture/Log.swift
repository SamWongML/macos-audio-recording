//  PROTOTYPE — throwaway. Answers issue #12: does a Core Audio process tap actually
//  capture Chrome and Safari audio, and does `CATapDescription.bundleIDs` solve the
//  helper-process problem? Not production code.
//
//  The log is the deliverable. Every event and every one-second tick lands both in the
//  window and in a file, so the run can be read back after the fact.

import Foundation

final class ProbeLog: @unchecked Sendable {
    static let shared = ProbeLog()

    private let lock = NSLock()
    private var buffer: [String] = []
    private var handle: FileHandle?
    private let start = Date()
    private(set) var path = "(no log file)"

    private init() {
        let directory = Bundle.main.object(forInfoDictionaryKey: "AppTapeProbeLogDirectory") as? String
            ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd-HHmmss"
        let file = "\(directory)/probe-\(stamp.string(from: start)).txt"
        FileManager.default.createFile(atPath: file, contents: nil)
        handle = FileHandle(forWritingAtPath: file)
        path = file

        let header = DateFormatter()
        header.dateFormat = "yyyy-MM-dd HH:mm:ss"
        write(raw: "# AppTape tap probe — issue #12")
        write(raw: "# started \(header.string(from: start))")
        // NB: no ProcessInfo.hostName here — it does a reverse-DNS lookup and hung the
        // main thread for minutes on this network.
        write(raw: "# os \(ProcessInfo.processInfo.operatingSystemVersionString)")
        write(raw: "")
    }

    /// `+MM:SS.mmm` since launch — the only clock that matters when correlating a log
    /// line against "the moment I clicked the tab".
    private func elapsed() -> String {
        let t = Date().timeIntervalSince(start)
        return String(format: "+%02d:%06.3f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }

    private func write(raw line: String) {
        lock.lock()
        buffer.append(line)
        if buffer.count > 4000 { buffer.removeFirst(buffer.count - 4000) }
        lock.unlock()
        if let data = (line + "\n").data(using: .utf8) {
            try? handle?.write(contentsOf: data)
        }
    }

    /// A state transition worth a line of its own.
    func event(_ text: String) { write(raw: "[\(elapsed())] EVENT  \(text)") }

    /// The once-a-second heartbeat: what the tap delivered in the last second.
    func tick(_ text: String) { write(raw: "[\(elapsed())] TICK   \(text)") }

    /// A human saying what they just did. Without these the log is uninterpretable.
    func mark(_ text: String) {
        write(raw: "")
        write(raw: "[\(elapsed())] MARK   ***  \(text)  ***")
    }

    func snapshot() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }
}
