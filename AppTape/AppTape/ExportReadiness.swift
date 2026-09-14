//
//  ExportReadiness.swift
//  AppTape
//

import Foundation

/// Whether an Export may start, and if not, what the user is told.
///
/// **Five ordered rules over six scalars**, ordered by what the user can do about each: a file that
/// will not decode is refused before anything else is asked of it; a Recording still being written
/// has an undefined Trim end (ADR-0012); a Trim holding nothing is the only refusal nothing else on
/// screen explains; an unencodable Quality Preset is already stated on its own rung at full strength
/// (ADR-0041), so the dock names the situation and leaves the specifics there; an Export already
/// running is the one the surfaces reach last and least (see `.alreadyRunning`).
///
/// **Two callers, which is the whole reason this is a type.** `ExportInspector` renders the reason in
/// the dock's sentence idiom (ADR-0042); `ExportCoordinator` refuses on it before a save panel opens.
/// The two used to hold separate copies — three different strings for one sentence, two different
/// units for one rule (the dock measured seconds, the coordinator measured frames), two rules the
/// coordinator did not have at all, and two more that were refused only as a side effect of
/// arithmetic in other files. None of it was tested, because none of it was reachable without a
/// window.
///
/// **Explicitly `nonisolated`, like `Trim`** (ADR-0022): `ExportEncoder.Failure.description` reads
/// `Reason.emptyTrim.sentence` from a `.utility` queue, and an unannotated type in this target is
/// main-actor isolated. The annotation is load-bearing, not decorative.
nonisolated enum ExportReadiness: Equatable {
    case ready
    case refused(Reason)

    /// Why an Export cannot start. Each case owns its sentence, so the wording exists once in the app.
    enum Reason: Equatable {
        /// A `public.audio`-typed file the decoder cannot open (ADR-0015). **Neither surface renders
        /// this**, and that is deliberate rather than an oversight: ADR-0034 took
        /// `AppTape can't decode this file` *out* of the trailing column — *"the trailing column holds
        /// the Export ladder or nothing, and never explains itself"* — and `EditorView.inspectorColumn`
        /// implements that by not rendering the dock at all for such a Recording, so neither a refusal
        /// nor a failed telling has anywhere to appear.
        ///
        /// It exists so `ExportCoordinator`'s gate has something to present rather than returning
        /// silently, and so the rule is *stated* instead of holding only because an unopenable file
        /// reads back as zero frames — which is what it rested on before. The sentence is the exact
        /// one ADR-0034 measured and removed, kept against that ADR's own closing note that *"a fourth
        /// pane could re-open this"*.
        case unopenable

        /// The `.caf` is still growing in place and its Trim end is undefined until Stop (ADR-0012).
        case stillCapturing

        /// Nothing in the Trim to encode — **including an adopted file with no audio in it**, which
        /// until now was refused only because `Trim(duration: 0).length` happens to be 0, an
        /// invariant established in `Trim.swift` and asserted nowhere.
        case emptyTrim

        /// The effective Quality Preset cannot encode this source faithfully (ADR-0015). Carries the
        /// rung's **own specific reason** — `AAC can't encode above 48 kHz — this file is 96 kHz.` —
        /// which `sentence` deliberately does not print; see below.
        case unencodable(String)

        /// An Export is already running — the rule that keeps the dock from ever offering a button
        /// whose click the coordinator would swallow.
        ///
        /// **Rarely reached, and kept for what it guarantees rather than what it shows.** Its named
        /// route was issue #127: a rename moved `recording.url` out from under a running job's
        /// `subjectURL`, and the Recording being exported lost its own progress bar to this sentence.
        /// The coordinator's subject follows a relocate now (ADR-0048). Two routes survive it, and
        /// they are why the rule stays: `presentSavePanel` falls back to a **modeless** panel when
        /// there is no key window, and a selection changed while that panel is up leaves `begin` to
        /// start on a Recording the editor has navigated away from; and a Recording re-adopted
        /// mid-Export (ADR-0021) leaves the telling on the object that was dropped, which a later
        /// rename then parts from the one on screen. In the coordinator the rule is stated rather
        /// than live: `export`'s `guard case .idle` returns before it can fire there at all.
        case alreadyRunning

        /// What the dock prints — ADR-0042's table, and the only wording for these five facts.
        ///
        /// **`.unencodable` names the situation and not the specifics, on purpose.** ADR-0041 already
        /// states this rung's own reason beside it, at full strength and outside everything that dims;
        /// ADR-0042's trade is that *"the dock names the situation and leaves the specifics to the
        /// rung"*. The specific reason rides along in the case's payload rather than being discarded,
        /// so a surface that has no rung beside it could still reach for it.
        var sentence: String {
            switch self {
            case .unopenable:     "AppTape can't decode this file."
            case .stillCapturing: "This Recording is still capturing."
            case .emptyTrim:      "Nothing in the Trim to export."
            case .unencodable:    "This quality can't encode this file."
            case .alreadyRunning: "An Export is already running."
            }
        }

        /// The glyph beside the sentence. A **name**, not a treatment — ADR-0042 keeps the glyph in
        /// the same ink as the words, so the app still has three marks under 3 : 1 rather than four.
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
    ///
    /// **`trimmedFrameCount`, never a duration in seconds.** Frames are what the encoder reads, and
    /// the two disagree on a Recording whose Trim is `isFixed`: a `Trim` carried over from a longer
    /// file, or a source whose header reports no sample rate, can report a positive length in seconds
    /// while `Recording.trimmedFrameRange` clamps to zero frames. The dock used to test seconds and
    /// the coordinator frames, so that Recording offered an `Export…` button whose click produced a
    /// *failure telling* — where ADR-0042 promises a sentence.
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
