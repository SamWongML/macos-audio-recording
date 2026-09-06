// PROTOTYPE (#79): contact sheet of the candidate icons, as the system renders them.
import AppKit

let args = CommandLine.arguments
let outPath = args[1]
let apps = Array(args.dropFirst(2))
let dark = ProcessInfo.processInfo.environment["DARK"] == "1"

let bigSize: CGFloat = 320
let smalls: [CGFloat] = [128, 64, 32, 16]
let pad: CGFloat = 36
let labelH: CGFloat = 30
let colW = bigSize + pad
let smallRowH: CGFloat = 140
let W = colW * CGFloat(apps.count) + pad
let H = pad + labelH + bigSize + smallRowH + pad

// The icon resolves its appearance at draw time, so the whole sheet is drawn inside
// the appearance under test. Painting a dark rectangle behind it proves nothing.
let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
appearance.performAsCurrentDrawingAppearance {
(dark ? NSColor(calibratedWhite: 0.14, alpha: 1) : NSColor(calibratedWhite: 0.93, alpha: 1)).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
    .foregroundColor: dark ? NSColor.white : NSColor.black,
]

for (i, path) in apps.enumerated() {
    let icon = NSWorkspace.shared.icon(forFile: path)
    let x = pad + CGFloat(i) * colW
    let name = (path as NSString).lastPathComponent
        .replacingOccurrences(of: ".app", with: "")
        .replacingOccurrences(of: "AppTape", with: "Variant ")
    (name as NSString).draw(at: NSPoint(x: x, y: H - pad - labelH + 6), withAttributes: attrs)
    icon.draw(in: NSRect(x: x, y: H - pad - labelH - bigSize, width: bigSize, height: bigSize))
    var sx = x
    let sy = H - pad - labelH - bigSize - smallRowH + 10
    for s in smalls {
        icon.draw(in: NSRect(x: sx, y: sy, width: s, height: s))
        sx += s + 18
    }
}
}
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
