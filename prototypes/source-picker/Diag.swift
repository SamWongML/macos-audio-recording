//  PROTOTYPE — throwaway diagnostic. Counts where redraws actually come from.
import Foundation

enum Diag {
    nonisolated(unsafe) static var counts: [String: Int] = [:]
    nonisolated(unsafe) static var enabled = ProcessInfo.processInfo.environment["DIAG"] == "1" || CommandLine.arguments.contains("diag")
    private static let lock = NSLock()

    static func hit(_ key: String) {
        guard enabled else { return }
        lock.lock(); counts[key, default: 0] += 1; lock.unlock()
    }

    static func start() {
        guard enabled else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            lock.lock(); let snapshot = counts; counts = [:]; lock.unlock()
            let line = snapshot.isEmpty ? "(no hits)" : snapshot.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)/s" }.joined(separator: " ")
            let data = ("DIAG " + line + "\n").data(using: .utf8)!
            FileHandle.standardError.write(data)
            if let handle = FileHandle(forWritingAtPath: "/tmp/ticks.log") {
                handle.seekToEndOfFile(); handle.write(data); handle.closeFile()
            } else {
                FileManager.default.createFile(atPath: "/tmp/ticks.log", contents: data)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
