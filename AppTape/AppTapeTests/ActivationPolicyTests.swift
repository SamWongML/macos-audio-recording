//
//  ActivationPolicyTests.swift
//  AppTapeTests
//

import Testing
import AppKit
@testable import AppTape

/// The flip is existence-based, not focus-based (ADR-0017): any open editor
/// window means `.regular`, only zero means `.accessory`.
struct ActivationPolicyTests {
    @Test func noEditorWindowIsAccessory() {
        #expect(ActivationPolicyController.policy(forOpenEditorCount: 0) == .accessory)
    }

    @Test func oneEditorWindowIsRegular() {
        #expect(ActivationPolicyController.policy(forOpenEditorCount: 1) == .regular)
    }

    @Test func moreThanOneStaysRegular() {
        #expect(ActivationPolicyController.policy(forOpenEditorCount: 2) == .regular)
    }
}
