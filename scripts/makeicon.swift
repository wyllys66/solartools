#!/usr/bin/env swift
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Wyllys Ingersoll
//
// makeicon.swift — render SolarBar's app icon at every size macOS wants and
// produce AppIcon.icns via `iconutil`.
//
// Output:
//   <output-dir>/AppIcon.icns      (final icon for the .app bundle)
//   <output-dir>/AppIcon.iconset/  (intermediate PNGs; safe to delete)
//
// Usage:
//   swift scripts/makeicon.swift [output-dir]
//
// The icon is a squircle with a warm yellow→orange gradient and a white
// `sun.max.fill` SF Symbol centered on top.

import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "build", isDirectory: true)

let iconsetDir = outputDir.appendingPathComponent("AppIcon.iconset")
let icnsFile   = outputDir.appendingPathComponent("AppIcon.icns")

// iconutil expects these exact filenames. (name, pixel dimension)
let variants: [(String, Int)] = [
    ("icon_16x16.png",        16),
    ("icon_16x16@2x.png",     32),
    ("icon_32x32.png",        32),
    ("icon_32x32@2x.png",     64),
    ("icon_128x128.png",     128),
    ("icon_128x128@2x.png",  256),
    ("icon_256x256.png",     256),
    ("icon_256x256@2x.png",  512),
    ("icon_512x512.png",     512),
    ("icon_512x512@2x.png", 1024),
]

func drawIcon(pixels: Int) -> NSImage {
    let size = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    // Apple's "squircle" corner radius is ~0.2237 of the icon edge.
    let cornerRadius = size * 0.2237

    // Clip to the squircle, then fill with a warm diagonal gradient.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect,
                       cornerWidth: cornerRadius,
                       cornerHeight: cornerRadius,
                       transform: nil))
    ctx.clip()

    let colors = [
        CGColor(red: 1.00, green: 0.82, blue: 0.22, alpha: 1.0),  // warm yellow
        CGColor(red: 0.95, green: 0.42, blue: 0.10, alpha: 1.0),  // orange
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: size),
                           end:   CGPoint(x: size, y: 0),
                           options: [])
    ctx.restoreGState()

    // Sun glyph — rendered white via palette configuration (macOS 13+).
    let sizeConfig    = NSImage.SymbolConfiguration(pointSize: size * 0.62, weight: .bold)
    let paletteConfig = NSImage.SymbolConfiguration(paletteColors: [.white])
    let config        = sizeConfig.applying(paletteConfig)

    if let base = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil),
       let sun  = base.withSymbolConfiguration(config) {
        let glyphSize = sun.size
        let origin = NSPoint(x: (size - glyphSize.width)  / 2,
                              y: (size - glyphSize.height) / 2)
        sun.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep  = NSBitmapImageRep(data: tiff),
          let png  = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "makeicon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "failed to encode PNG"])
    }
    try png.write(to: url)
}

let fm = FileManager.default
try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for (name, px) in variants {
    let img = drawIcon(pixels: px)
    try writePNG(img, to: iconsetDir.appendingPathComponent(name))
}

// Stitch into .icns.
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "-o", icnsFile.path, iconsetDir.path]
try task.run()
task.waitUntilExit()
if task.terminationStatus != 0 {
    FileHandle.standardError.write(Data("iconutil failed with status \(task.terminationStatus)\n".utf8))
    exit(1)
}

print("wrote \(icnsFile.path)")
