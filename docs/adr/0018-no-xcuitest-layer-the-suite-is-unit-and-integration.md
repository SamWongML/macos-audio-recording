---
status: accepted
---

# AppTape ships no XCUITest layer; the suite is unit and integration tests

AppTape's test suite is unit and integration tests (Swift Testing / XCTest), run
in-process against the app's types — 183 of them at the time of this decision.
There is **no XCUITest target**. The `AppTapeUITests` bundle the scaffold created
(issue #11) is deleted, target and source both.

That bundle was never a decision. It was untouched Xcode boilerplate — an empty
`testExample()` that only called `app.launch()`, plus a `testLaunchPerformance()`
launch-metric stub — carrying zero coverage since the scaffold commit. And it was
not merely inert: it was the only red in the suite. On macOS 27 its runner was
SIGKILL'd *before establishing connection* — "operation never finished
bootstrapping" — so neither method ever ran, and the whole test action reported
failure on account of a target that tested nothing.

The failure is structural, not incidental. XCUITest drives an app the way a user
would, which needs a foreground UI to attach to. AppTape launches `.accessory`
with no Dock icon, no menu bar, and a launch-suppressed editor (ADR-0017): at
launch there is deliberately nothing on screen for the runner to reach, so it
fails to bootstrap. UI-testing a menu-bar `LSUIElement` utility is an awkward fit
by construction, and the empty template hit exactly that wall.

## Considered options

**Keep the target and make it pass** — rewrite the test to open the editor window
first so the runner has a window to attach to, grant Accessibility to the runner,
drop the launch-perf stub, and move it to its own scheme so its slowness never
taxes the unit loop. Rejected: this is writing AppTape's first *real* UI test from
scratch, it stays flaky on the beta OS, and for a utility of this size the end-to-end
coverage it would buy is small next to its maintenance and wall-clock cost. If that
coverage is ever wanted, it is new work, not a repair of a template.

**Skip the target via a test plan** — add an `.xctestplan` that excludes
`AppTapeUITests` from the test action. Rejected: it leaves a dead, never-built,
never-run target in the project as a standing invitation to confusion, and the
project has no shared scheme or test plan today, so this would add configuration to
preserve something valueless.

**Delete the target** — chosen. It matches how the wider ecosystem treats an unused
UI-test bundle and how Apple frames the test pyramid (below).

## Consequences

**The pyramid keeps its shape.** Apple's guidance (WWDC 2018, "Testing Tips &
Tricks") is a broad base of fast unit tests, a smaller band of integration tests,
"topped off by a *handful* of end-to-end system tests, most often… UI tests." The
operative word is a handful of *real* ones. An empty `testExample()` was never that
apex — it was overhead. The 183 unit and integration tests are the base the pyramid
wants; removing the empty top removes nothing from coverage.

**Xcode stops building dead code, and nobody runs slow tests in the fast loop.**
The standing advice for an unused UITests target (e.g. Jon Reid, Quality Coding) is
to delete it outright rather than deselect it, so it cannot be built or run by
accident and cannot contaminate the fast unit feedback cycle. Deletion, not a skip
flag, is the form that advice takes.

**If UI coverage is wanted later, add a purpose-built target — don't resurrect the
template.** Create a fresh UI Testing Bundle in its **own scheme / test plan**
(keep slow UI tests off the unit path), and write tests that open the editor window
before asserting, so the runner has a `.regular` window to attach to (ADR-0017).
Swift Testing does not change this: it covers unit and integration, but UI
automation remains XCUITest-only, so "no UI target" simply means no XCUITest layer —
a deliberate, appropriate choice for a menu-bar utility, not a gap left by
oversight.

**The change is a plain git-tracked deletion**, fully reversible, touching only the
project file and the removed source.

Sources: [WWDC 2018 – Testing Tips & Tricks](https://developer.apple.com/videos/play/wwdc2018/417/);
[Quality Coding – Optimize Your Xcode Project for Fast Test Feedback](https://qualitycoding.org/optimize-xcode-for-fast-tests/).

Prompted by the macOS 27 test-suite failure in which the UI-test runner crashed on
launch while all 183 unit and integration tests passed.
