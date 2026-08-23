//  PROTOTYPE — throwaway diagnostics. Counts redraws and times the expensive passes.
import Foundation

enum Diag {
    nonisolated(unsafe) static var counts: [String: Int] = [:]
    nonisolated(unsafe) static var enabled = ProcessInfo.processInfo.environment["DIAG"] == "1"
        || CommandLine.arguments.contains("diag")
    private static let lock = NSLock()

    static func hit(_ key: String) {
        guard enabled else { return }
        lock.lock(); counts[key, default: 0] += 1; lock.unlock()
    }

    /// Always logged, DIAG or not — these are the numbers the ticket is actually asking for.
    /// Goes to a file as well as stderr: launching with `open` (the only launch that shows
    /// windows) leaves stderr nowhere useful.
    static let logPath = "/tmp/editor-window-prototype.log"

    static func note(_ line: String) {
        let data = ("NOTE " + line + "\n").data(using: .utf8)!
        FileHandle.standardError.write(data)
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile(); handle.write(data); handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data)
        }
    }

    static func time<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let value = try body()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        note(String(format: "%@ %.1f ms", label, ms))
        return value
    }

    static func start() {
        guard enabled else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            lock.lock(); let snapshot = counts; counts = [:]; lock.unlock()
            let line = snapshot.isEmpty ? "(no hits)" : snapshot.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)/s" }.joined(separator: " ")
            FileHandle.standardError.write(("DIAG " + line + "\n").data(using: .utf8)!)
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
