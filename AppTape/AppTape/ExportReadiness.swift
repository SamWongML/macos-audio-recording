import Foundation

/// Whether an Export may start, and if not, what the user is told.
nonisolated enum ExportReadiness: Equatable {
    case ready
    case refused(Reason)

    /// Why an Export cannot start. Each case owns its sentence, so the wording exists once in the app.
    enum Reason: Equatable {
        /// A `public.audio`-typed file the decoder cannot open. **Neither surface renders
        /// this**, and that is deliberate rather than an oversight: took
        /// `AppTape can't decode this file` *out* of the trailing column — *"the trailing column holds
        /// the Export ladder or nothing, and never explains itself"* — and `EditorView.inspectorColumn`
        /// implements that by not rendering the dock at all for such a Recording, so neither a refusal
        /// nor a failed telling has anywhere to appear.
        case unopenable

        /// The `.caf` is still growing in place and its Trim end is undefined until Stop.
        case stillCapturing

        /// Nothing in the Trim to encode — **including an adopted file with no audio in it**, which
        /// until now was refused only because `Trim(duration: 0).length` happens to be 0, an
        /// invariant established in `Trim.swift` and asserted nowhere.
        case emptyTrim

        /// The effective Quality Preset cannot encode this source faithfully. Carries the
        /// rung's **own specific reason** — `AAC can't encode above 48 kHz — this file is 96 kHz.` —
        /// which `sentence` deliberately does not print; see below.
        case unencodable(String)

        /// An Export is already running — the rule that keeps the dock from ever offering a button
        /// whose click the coordinator would swallow.
        case alreadyRunning

        /// What the dock prints — 's table, and the only wording for these five facts.
        var sentence: String {
            switch self {
            case .unopenable:     "AppTape can't decode this file."
            case .stillCapturing: "This Recording is still capturing."
            case .emptyTrim:      "Nothing in the Trim to export."
            case .unencodable:    "This quality can't encode this file."
            case .alreadyRunning: "An Export is already running."
            }
        }

        /// The glyph beside the sentence. A **name**, not a treatment — keeps the glyph in
        /// the same ink as the words, so the app still has three marks under 3: 1 rather than four.
        /// `RowRecordGlyph.symbolName` is the precedent for a pure module owning one, and owning it
        /// here is what lets the dock draw every refusal through a single call: the still-capturing
        /// sentence used to need a branch of its own solely because its glyph differed.
        var symbolName: String {
            self == .stillCapturing ? "record.circle" : "square.and.arrow.up"
        }
    }

    /// The refusal, or nil when an Export may start — the shape both call sites want.
    var blocker: Reason? {
        switch self {
        case .ready: nil
        case .refused(let reason): reason
        }
    }

    /// The decision. First rule that matches wins, in declaration order.
    static func evaluate(isOpenable: Bool,
                         isCapturing: Bool,
                         trimmedFrameCount: Int64,
                         preset: QualityPreset,
                         format: SourceFormat,
                         isExporting: Bool) -> ExportReadiness {
        if !isOpenable { return .refused(.unopenable) }
        if isCapturing { return .refused(.stillCapturing) }
        if trimmedFrameCount <= 0 { return .refused(.emptyTrim) }
        if case .unavailable(let reason) = preset.encodability(for: format) {
            return .refused(.unencodable(reason))
        }
        if isExporting { return .refused(.alreadyRunning) }
        return .ready
    }
}
