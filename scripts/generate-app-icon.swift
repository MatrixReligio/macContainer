#!/usr/bin/swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct IconSlot {
    let filename: String
    let points: Int
    let scale: Int

    var pixels: Int {
        points * scale
    }

    var sizeValue: String {
        "\(points)x\(points)"
    }

    var scaleValue: String {
        "\(scale)x"
    }
}

private let slots = [
    IconSlot(filename: "icon_16x16.png", points: 16, scale: 1),
    IconSlot(filename: "icon_16x16@2x.png", points: 16, scale: 2),
    IconSlot(filename: "icon_32x32.png", points: 32, scale: 1),
    IconSlot(filename: "icon_32x32@2x.png", points: 32, scale: 2),
    IconSlot(filename: "icon_128x128.png", points: 128, scale: 1),
    IconSlot(filename: "icon_128x128@2x.png", points: 128, scale: 2),
    IconSlot(filename: "icon_256x256.png", points: 256, scale: 1),
    IconSlot(filename: "icon_256x256@2x.png", points: 256, scale: 2),
    IconSlot(filename: "icon_512x512.png", points: 512, scale: 1),
    IconSlot(filename: "icon_512x512@2x.png", points: 512, scale: 2)
]

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("App icon generation FAIL: \(message)\n".utf8))
    exit(EXIT_FAILURE)
}

private func arguments() -> (input: URL, output: URL) {
    let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    var input = current.appendingPathComponent("Design/AppIcon/MacContainer-master.png")
    var output = current.appendingPathComponent(
        "App/MacContainer/Resources/Assets.xcassets/AppIcon.appiconset",
        isDirectory: true
    )

    var index = 1
    while index < CommandLine.arguments.count {
        let option = CommandLine.arguments[index]
        guard index + 1 < CommandLine.arguments.count else {
            fail("missing value for \(option)")
        }
        let value = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        switch option {
        case "--input": input = value
        case "--output": output = value
        default: fail("unknown option \(option)")
        }
        index += 2
    }
    return (input, output)
}

private func superellipsePath(size: Int) -> CGPath {
    let dimension = CGFloat(size)
    let inset = dimension * 0.018
    let center = dimension / 2
    let radius = (dimension - inset * 2) / 2
    let exponent = 5.0
    let path = CGMutablePath()

    for step in 0 ... 512 {
        let angle = CGFloat(step) / 512 * .pi * 2
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = center + radius * copysign(pow(abs(cosine), 2 / exponent), cosine)
        let y = center + radius * copysign(pow(abs(sine), 2 / exponent), sine)
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

private func render(source: CGImage, size: Int) -> CGImage {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: size,
              height: size,
              bitsPerComponent: 8,
              bytesPerRow: size * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else {
        fail("could not create \(size)x\(size) sRGB context")
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.addPath(superellipsePath(size: size))
    context.clip()
    context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))

    guard let image = context.makeImage() else {
        fail("could not render \(size)x\(size) image")
    }
    return image
}

private func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fail("could not create PNG destination \(url.path)")
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fail("could not finalize PNG \(url.path)")
    }
}

let paths = arguments()
guard let sourceHandle = CGImageSourceCreateWithURL(paths.input as CFURL, nil),
      let source = CGImageSourceCreateImageAtIndex(sourceHandle, 0, nil)
else {
    fail("could not decode master at \(paths.input.path)")
}

guard source.width == source.height, source.width >= 1024 else {
    fail("master must be square and at least 1024 pixels")
}

do {
    try FileManager.default.createDirectory(at: paths.output, withIntermediateDirectories: true)
} catch {
    fail("could not create output directory: \(error)")
}

for slot in slots {
    writePNG(render(source: source, size: slot.pixels), to: paths.output.appendingPathComponent(slot.filename))
}

let catalog: [String: Any] = [
    "images": slots.map { slot in
        [
            "filename": slot.filename,
            "idiom": "mac",
            "scale": slot.scaleValue,
            "size": slot.sizeValue
        ]
    },
    "info": ["author": "xcode", "version": 1]
]

do {
    let data = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
    try (data + Data("\n".utf8)).write(to: paths.output.appendingPathComponent("Contents.json"), options: .atomic)
} catch {
    fail("could not write Contents.json: \(error)")
}

print("Generated AppIcon: \(slots.count) slots from \(source.width)x\(source.height) master")
