#!/usr/bin/env swift

import AppKit
import Foundation

struct ScreenshotDesign {
    let id: String
    let headline: String
    let subcopy: String
    let background: NSColor
    let accent: NSColor
}

enum DeviceFrame: Equatable {
    case phone
    case tablet
}

extension NSColor {
    convenience init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)
        self.init(
            calibratedRed: CGFloat((number >> 16) & 0xff) / 255,
            green: CGFloat((number >> 8) & 0xff) / 255,
            blue: CGFloat(number & 0xff) / 255,
            alpha: 1
        )
    }
}

let designs = [
    ScreenshotDesign(
        id: "01-Home-Hierarchy",
        headline: "A map for\nyour stuff",
        subcopy: "Organize homes, rooms, shelves, drawers, and boxes the way you actually look for things.",
        background: NSColor(hex: "#F8F0E4"),
        accent: NSColor(hex: "#C2672D")
    ),
    ScreenshotDesign(
        id: "02-Flagged-Items",
        headline: "Keep essentials\nclose",
        subcopy: "Flag passports, tools, documents, and anything you cannot afford to hunt for later.",
        background: NSColor(hex: "#F3F7EA"),
        accent: NSColor(hex: "#476D3A")
    ),
    ScreenshotDesign(
        id: "03-Search",
        headline: "Search your\nwhole home",
        subcopy: "Type what you remember and CubbyLog narrows every room, container, and item.",
        background: NSColor(hex: "#EAF5F6"),
        accent: NSColor(hex: "#2F6F73")
    ),
    ScreenshotDesign(
        id: "04-Item-Details",
        headline: "Save the details\nthat matter",
        subcopy: "Track notes, quantity, serials, dates, value, warranty info, and custom fields.",
        background: NSColor(hex: "#F4EEF7"),
        accent: NSColor(hex: "#7D4C8E")
    )
]

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("Usage: frame_screenshots.swift <screenshots-directory>\n".data(using: .utf8)!)
    exit(2)
}

let rootURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
let fileManager = FileManager.default

guard let enumerator = fileManager.enumerator(
    at: rootURL,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
) else {
    FileHandle.standardError.write("Unable to read screenshots directory: \(rootURL.path)\n".data(using: .utf8)!)
    exit(1)
}

var framedCount = 0

for case let fileURL as URL in enumerator {
    guard fileURL.pathExtension.lowercased() == "png" else { continue }
    guard let design = designs.first(where: { fileURL.lastPathComponent.contains($0.id) }) else {
        try fileManager.removeItem(at: fileURL)
        print("Removed unmatched screenshot \(fileURL.path)")
        continue
    }

    do {
        try frameScreenshot(at: fileURL, design: design)
        framedCount += 1
        print("Framed \(fileURL.path)")
    } catch {
        FileHandle.standardError.write("Failed to frame \(fileURL.path): \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

guard framedCount > 0 else {
    FileHandle.standardError.write("No matching screenshots found under \(rootURL.path)\n".data(using: .utf8)!)
    exit(1)
}

func frameScreenshot(at fileURL: URL, design: ScreenshotDesign) throws {
    let data = try Data(contentsOf: fileURL)
    guard let bitmap = NSBitmapImageRep(data: data) else {
        throw NSError(domain: "FrameScreenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG could not be decoded"])
    }

    let sourceSize = NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
    let sourceImage = NSImage(size: sourceSize)
    sourceImage.addRepresentation(bitmap)

    let outputBitmap = try makeBitmap(size: sourceSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: outputBitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let frame: DeviceFrame = fileURL.lastPathComponent.localizedCaseInsensitiveContains("ipad") ? .tablet : .phone
    drawBackground(size: sourceSize, design: design)
    drawCopy(size: sourceSize, design: design, frame: frame)
    drawDevice(sourceImage: sourceImage, canvasSize: sourceSize, frame: frame)
    NSGraphicsContext.restoreGraphicsState()

    guard let jpeg = outputBitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.98]) else {
        throw NSError(domain: "FrameScreenshots", code: 3, userInfo: [NSLocalizedDescriptionKey: "Framed JPEG could not be encoded"])
    }

    let jpegURL = fileURL.deletingPathExtension().appendingPathExtension("jpg")
    try jpeg.write(to: jpegURL, options: .atomic)
    try fileManager.removeItem(at: fileURL)
}

func makeBitmap(size: NSSize) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "FrameScreenshots", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bitmap context could not be created"])
    }

    return bitmap
}

func drawBackground(size: NSSize, design: ScreenshotDesign) {
    design.background.setFill()
    NSRect(origin: .zero, size: size).fill()

    let bandHeight = size.height * 0.042
    let bandRect = NSRect(x: 0, y: 0, width: size.width, height: bandHeight)
    design.accent.withAlphaComponent(0.92).setFill()
    bandRect.fill()

    design.accent.withAlphaComponent(0.08).setFill()
    let lowerBand = NSRect(x: 0, y: 0, width: size.width, height: size.height * 0.34)
    lowerBand.fill()
}

func drawCopy(size: NSSize, design: ScreenshotDesign, frame _: DeviceFrame) {
    let textColor = NSColor(hex: "#15191C")
    let headlineFontSize = min(106, size.width * 0.082)
    let subcopyFontSize = min(43, size.width * 0.033)
    let headlineFont = NSFont.systemFont(ofSize: headlineFontSize, weight: .heavy)
    let subcopyFont = NSFont.systemFont(ofSize: subcopyFontSize, weight: .medium)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = 2

    let headlineAttributes: [NSAttributedString.Key: Any] = [
        .font: headlineFont,
        .foregroundColor: textColor,
        .paragraphStyle: paragraph
    ]
    let subcopyAttributes: [NSAttributedString.Key: Any] = [
        .font: subcopyFont,
        .foregroundColor: textColor.withAlphaComponent(0.78),
        .paragraphStyle: paragraph
    ]

    let headlineRect = rectFromTop(
        x: size.width * 0.09,
        y: size.height * 0.045,
        width: size.width * 0.82,
        height: size.height * 0.120,
        canvasHeight: size.height
    )
    let subcopyRect = rectFromTop(
        x: size.width * 0.13,
        y: size.height * 0.155,
        width: size.width * 0.74,
        height: size.height * 0.055,
        canvasHeight: size.height
    )

    NSAttributedString(string: design.headline, attributes: headlineAttributes).draw(
        with: headlineRect,
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    NSAttributedString(string: design.subcopy, attributes: subcopyAttributes).draw(
        with: subcopyRect,
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
}

func drawDevice(sourceImage: NSImage, canvasSize: NSSize, frame: DeviceFrame) {
    let aspect = sourceImage.size.height / sourceImage.size.width
    let frameInset = frame == .tablet ? max(26, canvasSize.width * 0.018) : max(28, canvasSize.width * 0.026)
    let deviceTop = canvasSize.height * 0.205
    let bottomMargin = canvasSize.height * 0.035
    let maxOuterWidth = canvasSize.width * (frame == .tablet ? 0.88 : 0.78)
    let maxOuterHeight = canvasSize.height - deviceTop - bottomMargin
    let screenWidth = min(maxOuterWidth - frameInset * 2, (maxOuterHeight - frameInset * 2) / aspect)
    let screenHeight = screenWidth * aspect
    let outerWidth = screenWidth + frameInset * 2
    let outerHeight = screenHeight + frameInset * 2
    let outerRect = rectFromTop(
        x: (canvasSize.width - outerWidth) / 2,
        y: deviceTop,
        width: outerWidth,
        height: outerHeight,
        canvasHeight: canvasSize.height
    )
    let screenRect = outerRect.insetBy(dx: frameInset, dy: frameInset)

    drawSideButtons(outerRect: outerRect, canvasSize: canvasSize, frame: frame)

    let shadow = NSShadow()
    shadow.shadowBlurRadius = canvasSize.width * 0.044
    shadow.shadowOffset = NSSize(width: 0, height: -canvasSize.height * 0.010)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.set()

    NSColor(hex: "#090B10").setFill()
    NSBezierPath(
        roundedRect: outerRect,
        xRadius: outerWidth * (frame == .phone ? 0.115 : 0.045),
        yRadius: outerWidth * (frame == .phone ? 0.115 : 0.045)
    ).fill()
    NSShadow().set()

    NSColor(hex: "#1A1D21").setStroke()
    let rimPath = NSBezierPath(
        roundedRect: outerRect.insetBy(dx: 3, dy: 3),
        xRadius: outerWidth * (frame == .phone ? 0.108 : 0.042),
        yRadius: outerWidth * (frame == .phone ? 0.108 : 0.042)
    )
    rimPath.lineWidth = max(2, canvasSize.width * 0.003)
    rimPath.stroke()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(
        roundedRect: screenRect,
        xRadius: screenWidth * (frame == .phone ? 0.075 : 0.030),
        yRadius: screenWidth * (frame == .phone ? 0.075 : 0.030)
    ).addClip()
    sourceImage.draw(
        in: screenRect,
        from: NSRect(origin: .zero, size: sourceImage.size),
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    if frame == .phone {
        drawDynamicIsland(screenRect: screenRect, screenWidth: screenWidth)
    } else {
        drawCameraDot(screenRect: screenRect, screenWidth: screenWidth)
    }
}

func drawSideButtons(outerRect: NSRect, canvasSize: NSSize, frame: DeviceFrame) {
    let sideButtonWidth = max(6, outerRect.width * (frame == .phone ? 0.010 : 0.006))
    let sideButtonRadius = sideButtonWidth / 2
    NSColor.black.withAlphaComponent(0.45).setFill()

    NSBezierPath(
        roundedRect: NSRect(
            x: outerRect.minX - sideButtonWidth,
            y: outerRect.maxY - outerRect.height * 0.30,
            width: sideButtonWidth,
            height: outerRect.height * 0.11
        ),
        xRadius: sideButtonRadius,
        yRadius: sideButtonRadius
    ).fill()

    NSBezierPath(
        roundedRect: NSRect(
            x: outerRect.maxX,
            y: outerRect.maxY - outerRect.height * 0.36,
            width: sideButtonWidth,
            height: outerRect.height * 0.15
        ),
        xRadius: sideButtonRadius,
        yRadius: sideButtonRadius
    ).fill()
}

func drawDynamicIsland(screenRect: NSRect, screenWidth: CGFloat) {
    let islandWidth = screenWidth * 0.30
    let islandHeight = screenWidth * 0.078
    let islandRect = NSRect(
        x: screenRect.midX - islandWidth / 2,
        y: screenRect.maxY - islandHeight - screenWidth * 0.034,
        width: islandWidth,
        height: islandHeight
    )
    NSColor.black.setFill()
    NSBezierPath(
        roundedRect: islandRect,
        xRadius: islandHeight / 2,
        yRadius: islandHeight / 2
    ).fill()
}

func drawCameraDot(screenRect: NSRect, screenWidth: CGFloat) {
    let dotSize = max(7, screenWidth * 0.014)
    let dotRect = NSRect(
        x: screenRect.midX - dotSize / 2,
        y: screenRect.maxY - dotSize - screenWidth * 0.018,
        width: dotSize,
        height: dotSize
    )
    NSColor.black.withAlphaComponent(0.8).setFill()
    NSBezierPath(ovalIn: dotRect).fill()
}

func rectFromTop(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, canvasHeight: CGFloat) -> NSRect {
    NSRect(x: x, y: canvasHeight - y - height, width: width, height: height)
}
