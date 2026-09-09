import Foundation

/// Throwaway. Prototype switch for issue #125 — what shape the Export control takes while it is
/// **blocked**. Never merged; the shipped build has one shape and no switch.
///
///   `a`  baseline — `.borderedProminent` with `.disabled()`, as shipped: 3.00 : 1 / 1.75 : 1
///   `b`  `.bordered` while blocked, `.borderedProminent` when available — a different *system*
///        control rather than an owned treatment, so the label sits on the column's ground and
///        only `.disabled()`'s own text dimming applies to it
///   `c`  prominent, label lifted out of the disabled scope — ADR-0041's move applied literally
///   `d`  no button at all while blocked: a sentence in the dock's own idiom, the shape
///        `exportControl` already uses for a Recording that is still capturing
///   `e`  `d` with the sentence in ink rather than `.secondary` — #119's own correction, where
///        `.secondary` reached only 3.81 : 1 in Light and ink reached 13.02 : 1
enum ExportButtonVariant: String {
    case a, b, c, d, e

    static let current = ExportButtonVariant(
        rawValue: ProcessInfo.processInfo.environment["APPTAPE_XBTN"] ?? "a") ?? .a
}
