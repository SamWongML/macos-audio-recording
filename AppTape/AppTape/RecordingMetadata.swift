//
//  RecordingMetadata.swift
//  AppTape
//

import Foundation

/// A Recording's metadata rides in **extended attributes on the file itself** (ADR-0006),
/// so the filename stays the name and the attributes survive a Finder move or an APFS
/// clone. This ticket writes only the Source; Trim and Gain join later behind the same
/// namespace. Losing the xattrs degrades gracefully — the audio is the file.
enum RecordingMetadata {
    /// The Source the Recording was captured from.
    static let sourceKey = "com.apptape.source"

    static func writeSource(_ source: String, to url: URL) throws {
        try write(source, forKey: sourceKey, to: url)
    }

    static func readSource(from url: URL) -> String? {
        read(forKey: sourceKey, from: url)
    }

    private static func write(_ value: String, forKey key: String, to url: URL) throws {
        let data = Data(value.utf8)
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            data.withUnsafeBytes { bytes in
                setxattr(path, key, bytes.baseAddress, data.count, 0, 0)
            }
        }
        if result != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private static func read(forKey key: String, from url: URL) -> String? {
        url.withUnsafeFileSystemRepresentation { path -> String? in
            let length = getxattr(path, key, nil, 0, 0, 0)
            guard length > 0 else { return nil }
            var data = Data(count: length)
            let read = data.withUnsafeMutableBytes { getxattr(path, key, $0.baseAddress, length, 0, 0) }
            guard read >= 0 else { return nil }
            return String(data: data.prefix(read), encoding: .utf8)
        }
    }
}
