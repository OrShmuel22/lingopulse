#!/usr/bin/env swift

// Stitches the three Quick Refine screenshots into an animated GIF for the
// README hero. Pure ImageIO + CoreGraphics — no external dependencies. Run
// from the repo root: `swift scripts/make-readme-gif.swift`.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas = CGSize(width: 760, height: 560)
let padding: CGFloat = 32
let perFrameDelaySeconds = 1.8
let backgroundColor = CGColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)

let inputs = [
    "docs/assets/quick-action-menu.png",
    "docs/assets/quick-refine-capture.png",
    "docs/assets/quick-refine-preview.png",
]
let output = "docs/assets/demo.gif"

func loadCGImage(_ path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func composeOnCanvas(_ image: CGImage) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
    guard let ctx = CGContext(
        data: nil,
        width: Int(canvas.width),
        height: Int(canvas.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else { return nil }

    ctx.setFillColor(backgroundColor)
    ctx.fill(CGRect(origin: .zero, size: canvas))

    let avail = CGSize(width: canvas.width - padding * 2, height: canvas.height - padding * 2)
    let imgSize = CGSize(width: image.width, height: image.height)
    let scale = min(avail.width / imgSize.width, avail.height / imgSize.height)
    let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
    let drawRect = CGRect(
        x: (canvas.width - drawSize.width) / 2,
        y: (canvas.height - drawSize.height) / 2,
        width: drawSize.width,
        height: drawSize.height
    )

    ctx.interpolationQuality = .high
    ctx.draw(image, in: drawRect)
    return ctx.makeImage()
}

let outURL = URL(fileURLWithPath: output)
guard let dest = CGImageDestinationCreateWithURL(
    outURL as CFURL,
    UTType.gif.identifier as CFString,
    inputs.count,
    nil
) else {
    FileHandle.standardError.write(Data("Failed to create GIF destination\n".utf8))
    exit(1)
}

let frameProps: [CFString: Any] = [
    kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFDelayTime: perFrameDelaySeconds
    ]
]

for path in inputs {
    guard let img = loadCGImage(path), let frame = composeOnCanvas(img) else {
        FileHandle.standardError.write(Data("Failed at \(path)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(dest, frame, frameProps as CFDictionary)
}

let gifProps: [CFString: Any] = [
    kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFLoopCount: 0
    ]
]
CGImageDestinationSetProperties(dest, gifProps as CFDictionary)

guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("Failed to finalize GIF\n".utf8))
    exit(1)
}

print("Wrote \(output)")
