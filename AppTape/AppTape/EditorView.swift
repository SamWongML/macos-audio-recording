//
//  EditorView.swift
//  AppTape
//

import SwiftUI

/// Placeholder editor window. The waveform and Trim surface is designed in
/// "Design the editor window: waveform and trim" (issue #7).
struct EditorView: View {
    var body: some View {
        ContentUnavailableView(
            "No Recording",
            systemImage: "waveform",
            description: Text("Recordings will open here.")
        )
        .frame(minWidth: 640, minHeight: 360)
    }
}

#Preview {
    EditorView()
}
