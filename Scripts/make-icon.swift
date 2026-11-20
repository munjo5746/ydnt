#!/usr/bin/env swift
// Renders the "nah." app icon (claude.ai/design concept 2e) into the asset catalog.
// Run from repo root: swift Scripts/make-icon.swift
// Geometry is the design's 1024 canvas, converted from SVG (y down) to Core Graphics (y up).
import AppKit

let dir = URL(fileURLWithPath: "YouDontNeedThat/Assets.xcassets/AppIcon.appiconset")
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [CGFloat(v >> 16 & 0xFF) / 255, CGFloat(v >> 8 & 0xFF) / 255, CGFloat(v & 0xFF) / 255, a])!
}

func render(_ px: Int) -> Data {
    let cg = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 1024
    cg.scaleBy(x: s, y: s)

    // Squircle tile: 824 on a 1024 canvas (Apple's macOS grid), vertical gradient #22232c → #111217.
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 24 * s, color: hex(0, 0.3))
    cg.addPath(tile); cg.setFillColor(hex(0x111217)); cg.fillPath()
    cg.restoreGState()
    cg.saveGState()
    cg.addPath(tile); cg.clip()
    let grad = CGGradient(colorsSpace: srgb, colors: [hex(0x22232C), hex(0x111217)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
    cg.restoreGState()

    // "nah" in bold mono, lime, letter-spacing -10, centered on x 486, baseline at SVG y 610.
    let text = NSAttributedString(string: "nah", attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 300, weight: .bold),
        .foregroundColor: NSColor(cgColor: hex(0xC6F24E))!,
        .kern: -10,
    ])
    let line = CTLineCreateWithAttributedString(text)
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    cg.textPosition = CGPoint(x: 486 - width / 2, y: 1024 - 610)
    CTLineDraw(line, cg)

    // The period: periwinkle dot.
    cg.setFillColor(hex(0x8188F5))
    cg.fillEllipse(in: CGRect(x: 790 - 34, y: 1024 - 590 - 34, width: 68, height: 68))

    return NSBitmapImageRep(cgImage: cg.makeImage()!).representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
var images: [String] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try render(pt * scale).write(to: dir.appending(path: name))
        images.append(#"{ "idiom" : "mac", "size" : "\#(pt)x\#(pt)", "scale" : "\#(scale)x", "filename" : "\#(name)" }"#)
    }
}
try #"{ "images" : [\#n    \#(images.joined(separator: ",\n    "))\#n  ],\#n  "info" : { "version" : 1, "author" : "xcode" }\#n}\#n"#
    .write(to: dir.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
try #"{ "info" : { "version" : 1, "author" : "xcode" } }"#
    .write(to: dir.deletingLastPathComponent().appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(images.count) icons to \(dir.path)")
// The menu bar icon is drawn in code: NSImage.menuBarIcon in YouDontNeedThatApp.swift.
