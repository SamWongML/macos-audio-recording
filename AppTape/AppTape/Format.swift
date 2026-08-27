//
//  Format.swift
//  AppTape
//

import Foundation

/// Time and size formatting shared by the editor's surfaces.
enum Format {
    /// `1:02` or `1:02:03` past the hour; `precise` adds hundredths (`1:02.34`) for the loupe
    /// and the playhead clock, where a Trim point is placed to the fraction of a second.
    static func time(_ seconds: Double, precise: Bool = false) -> String {
        let s = max(0, seconds)
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60, sec = Int(s) % 60
        let frac = Int((s - s.rounded(.down)) * 100)
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return precise ? String(format: "%d:%02d.%02d", m, sec, frac)
                       : String(format: "%d:%02d", m, sec)
    }
}
