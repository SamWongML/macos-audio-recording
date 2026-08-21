# Sign local builds with a free Personal Team, never "Sign to Run Locally"

TCC keys every permission grant to the code signature's **designated requirement**, not to the bundle identifier alone. Xcode's "Sign to Run Locally" produces an ad-hoc signature with no stable designated requirement, so every rebuild looks like a different application to TCC and the System Audio Recording grant resets — the app re-prompts, or worse, silently receives nothing. Confirmed by Apple technotes TN3127 and TN3179 and by an Apple DTS engineer on two Developer Forums threads.

**So: sign with a free Personal Team ("Apple Development" identity) and keep the bundle identifier fixed forever.** This costs nothing — no paid Developer Program enrollment — and it is the only thing that makes permission grants survive rebuilds on one machine.

This is recorded as an ADR because it is a build-setting constraint invisible in the source. "It's a local-only app, ad-hoc signing is simpler" is the obvious-looking simplification, and taking it breaks permissions in a way that presents as a mysterious silent-audio bug rather than as a signing problem.

The bundle identifier is equally load-bearing: every grant is keyed to it, so changing it later orphans every prior grant.

Full research, with citations: `docs/research/tcc-permissions.md` on branch `research/tcc-permissions`, and issue #3.
