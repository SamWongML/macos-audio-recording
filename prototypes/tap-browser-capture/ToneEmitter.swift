//  PROTOTYPE — throwaway. A control for issue #12: an ordinary .app bundle, with an
//  ordinary bundle ID, that is its own HAL client and does nothing but emit a tone.
//
//  It exists to separate two explanations for `bundleIDs` failing against Safari: either
//  the property is broken generally, or it cannot reach audio hosted in an XPC service
//  (`com.apple.WebKit.GPU`) as opposed to an app.

import AVFoundation
import AppKit

@main
struct ToneEmitter {
    static func main() {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        var phase: Float = 0
        let increment = 2 * Float.pi * 440 / 48000

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let value = sin(phase) * 0.25
                phase += increment
                if phase > 2 * .pi { phase -= 2 * .pi }
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try? engine.start()

        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.run()
    }
}
