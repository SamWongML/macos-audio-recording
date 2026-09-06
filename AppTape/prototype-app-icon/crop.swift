import AppKit
let a = CommandLine.arguments
let src = NSImage(contentsOfFile: a[1])!
var r = NSRect(x: Double(a[3])!, y: Double(a[4])!, width: Double(a[5])!, height: Double(a[6])!)
let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let cropped = cg.cropping(to: r)!
let rep = NSBitmapImageRep(cgImage: cropped)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
print("\(cropped.width)x\(cropped.height)")
