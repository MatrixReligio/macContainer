#!/usr/bin/swift

import CoreGraphics
import Foundation
import ImageIO

private struct IconSlot: Hashable {
    let filename: String
    let points: Int
    let scale: Int

    var pixels: Int {
        points * scale
    }

    var catalogKey: String {
        "\(filename)|mac|\(points)x\(points)|\(scale)x"
    }
}

private struct Catalog: Decodable {
    struct Image: Decodable {
        let filename: String
        let idiom: String
        let scale: String
        let size: String
    }

    let images: [Image]
}

private struct Arguments {
    let sourceArtwork: URL
    let appIconSet: URL
}

private struct AlphaMetrics {
    let corners: [UInt8]
    let center: UInt8
    let visibleRatio: Double
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

private func fail(_ messages: [String]) -> Never {
    for message in messages.sorted() {
        FileHandle.standardError.write(Data("App icon check FAIL: \(message)\n".utf8))
    }
    exit(EXIT_FAILURE)
}

private func arguments() -> Arguments {
    var sourceArtwork: URL?
    var appIconSet: URL?
    var index = 1
    while index < CommandLine.arguments.count {
        let option = CommandLine.arguments[index]
        guard index + 1 < CommandLine.arguments.count else { fail(["missing value for \(option)"]) }
        let value = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        switch option {
        case "--master": sourceArtwork = value
        case "--app-icon-set": appIconSet = value
        default: fail(["unknown option \(option)"])
        }
        index += 2
    }
    guard let sourceArtwork, let appIconSet else {
        fail(["usage: check-app-icon.swift --master <png> --app-icon-set <appiconset>"])
    }
    return Arguments(sourceArtwork: sourceArtwork, appIconSet: appIconSet)
}

private func image(at url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

private func alphaMetrics(for image: CGImage) -> AlphaMetrics? {
    let size = image.width
    guard size == image.height,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: size,
              height: size,
              bitsPerComponent: 8,
              bytesPerRow: size * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ),
          let data = context.data
    else {
        return nil
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let pixels = data.assumingMemoryBound(to: UInt8.self)
    func alpha(x: Int, y: Int) -> UInt8 {
        pixels[(y * size + x) * 4 + 3]
    }

    let corners = [
        alpha(x: 0, y: 0),
        alpha(x: size - 1, y: 0),
        alpha(x: 0, y: size - 1),
        alpha(x: size - 1, y: size - 1)
    ]
    let center = alpha(x: size / 2, y: size / 2)
    var visible = 0
    for index in 0 ..< size * size where pixels[index * 4 + 3] > 16 {
        visible += 1
    }
    return AlphaMetrics(corners: corners, center: center, visibleRatio: Double(visible) / Double(size * size))
}

private let paths = arguments()
var errors: [String] = []

if let sourceArtwork = image(at: paths.sourceArtwork) {
    if sourceArtwork.width != sourceArtwork.height || sourceArtwork.width < 1024 {
        errors.append("source artwork must be square and at least 1024 pixels")
    }
} else {
    errors.append("source artwork is missing or undecodable")
}

let contentsURL = paths.appIconSet.appendingPathComponent("Contents.json")
if let data = try? Data(contentsOf: contentsURL), let catalog = try? JSONDecoder().decode(Catalog.self, from: data) {
    let actual = Set(catalog.images.map { "\($0.filename)|\($0.idiom)|\($0.size)|\($0.scale)" })
    let expected = Set(slots.map(\.catalogKey))
    if actual != expected {
        errors.append("Contents.json does not declare the exact ten canonical macOS slots")
    }
} else {
    errors.append("Contents.json is missing or invalid")
}

let expectedFiles = Set(slots.map(\.filename))
let actualFiles = Set(
    ((try? FileManager.default.contentsOfDirectory(atPath: paths.appIconSet.path)) ?? [])
        .filter { $0.hasSuffix(".png") }
)
if actualFiles != expectedFiles {
    errors.append("PNG file set differs from the ten declared slots")
}

for slot in slots {
    let url = paths.appIconSet.appendingPathComponent(slot.filename)
    guard let data = try? Data(contentsOf: url),
          data.starts(with: [0x89, 0x50, 0x4E, 0x47]),
          let icon = image(at: url)
    else {
        errors.append("\(slot.filename) is missing or is not PNG")
        continue
    }
    if icon.width != slot.pixels || icon.height != slot.pixels {
        errors.append("\(slot.filename) must be \(slot.pixels)x\(slot.pixels)")
    }
    if icon.colorSpace?.name != CGColorSpace.sRGB {
        errors.append("\(slot.filename) must use the sRGB color space")
    }
    guard let metrics = alphaMetrics(for: icon) else {
        errors.append("\(slot.filename) could not be sampled")
        continue
    }
    if metrics.corners.contains(where: { $0 > 8 }) {
        errors.append("\(slot.filename) corners must be transparent")
    }
    if metrics.center < 245 {
        errors.append("\(slot.filename) center must be opaque")
    }
    if !(0.70 ... 0.97).contains(metrics.visibleRatio) {
        errors.append("\(slot.filename) visible coverage is outside 70% through 97%")
    }
}

if !errors.isEmpty {
    fail(errors)
}

print("App icon check PASS: 10 slots, sRGB, alpha mask, canonical dimensions")
