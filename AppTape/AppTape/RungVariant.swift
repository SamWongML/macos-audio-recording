import Foundation

/// Throwaway. Prototype switch for issue #119 — how an *unencodable* Quality Preset rung states
/// its reason. Never merged; the shipped build has one shape and no switch.
///
///   `a`  baseline — orange sentence, whole row at `.opacity(0.5)`
///   `b`  ADR-0037 mechanically: orange ⚠ mark, sentence takes ink; row still halved
///   `c`  the reason is exempt from the row's dimming and takes ink; no estimate, no glyph
///   `d`  `c` with the reason `.secondary` at full strength rather than `.primary`
///   `e`  the reason lifted *out* of the disabled Button entirely, in ink, so nothing dims it
///   `f`  `e` with the reason `.secondary` — the available rung's codec-label treatment
enum RungVariant: String {
    case a, b, c, d, e, f

    static let current = RungVariant(rawValue: ProcessInfo.processInfo.environment["APPTAPE_RUNG"] ?? "a") ?? .a

    /// `a`/`b` halve the whole row; `c`/`d` halve only the parts that carry "unavailable".
    var dimsWholeRow: Bool { self == .a || self == .b }
    /// `e` lifts the reason clear of the Button, so `.disabled()`'s own dimming never reaches it.
    var reasonOutsideButton: Bool { self == .e || self == .f }
    /// `c`/`d` drop the size estimate on a rung that cannot encode (ADR-0031's rule, second cause).
    var dropsEstimate: Bool { self == .c || self == .d || self == .e || self == .f }
    var hasMark: Bool { self == .b }
}
