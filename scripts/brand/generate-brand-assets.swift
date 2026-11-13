#!/usr/bin/env swift
//
//  generate-brand-assets.swift
//  Kannu
//
//  Copyright (C) 2026 Kannu contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

// Draws Kannu's logo and its install window, and writes every file that carries them:
//
//     swift scripts/brand/generate-brand-assets.swift
//
// The outputs are committed, so this only runs when the artwork changes. It is not part of the app
// build, and neither Instrument Serif nor anything else in this folder ships in the app.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let brandDir = URL(fileURLWithPath: #filePath).standardizedFileURL.deletingLastPathComponent()
let repoRoot = brandDir.deletingLastPathComponent().deletingLastPathComponent()

// MARK: - Palette

func srgb(_ hex: UInt32) -> CGColor {
    CGColor(
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
            1,
        ])!
}

let ink = srgb(0x101114)
let lidLight = srgb(0xF4F1EA)
let pupilBlue = srgb(0x4DA3FF)
let paper = srgb(0xF5EFE3)
let headingInk = srgb(0x25211A)
let arrowAmber = srgb(0xC97A12)

// MARK: - Files

func makeContext(width: Int, height: Int, opaque: Bool) -> CGContext {
    CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
}

func writePNG(_ context: CGContext, to url: URL, dpi: Int = 72) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
    CGImageDestinationAddImage(destination, context.makeImage()!, properties)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
}

// MARK: - The eye

/// One almond eye, in the 1024-unit space of the icon, centred on the origin.
///
/// Small sizes are redrawn, not scaled: at 1 pixel = 64 units a 38-unit lid is under a pixel wide and
/// anti-aliases to grey. KannuIcon-32 and -64 are also what 16 pt and 32 pt use on a Retina display.
/// Their numbers land the lids and the pupil's edge on whole pixels, because the pupil is centred on
/// the canvas: at 16 pixels the lids are 3.5 pixels out and the pupil is 4 pixels across.
struct EyeShape {
    let lidWidth: CGFloat
    let halfWidth: CGFloat
    let upperLid: CGFloat
    let lowerLid: CGFloat
    let pupilRadius: CGFloat

    static func forIcon(pixels: Int) -> EyeShape {
        switch pixels {
        case ...16:
            return EyeShape(lidWidth: 80, halfWidth: 368, upperLid: 224, lowerLid: 224, pupilRadius: 128)
        case ...32:
            return EyeShape(lidWidth: 64, halfWidth: 340, upperLid: 212, lowerLid: 172, pupilRadius: 96)
        case ...64:
            return EyeShape(lidWidth: 48, halfWidth: 320, upperLid: 192, lowerLid: 156, pupilRadius: 88)
        default:
            return EyeShape(lidWidth: 38, halfWidth: 306, upperLid: 180, lowerLid: 146, pupilRadius: 86)
        }
    }

    func draw(in context: CGContext) {
        // A cubic's midpoint sits at 3/4 of its control height, so divide to land on the lid height.
        let reach = halfWidth * 0.46
        let almond = CGMutablePath()
        almond.move(to: CGPoint(x: -halfWidth, y: 0))
        almond.addCurve(
            to: CGPoint(x: halfWidth, y: 0),
            control1: CGPoint(x: -reach, y: upperLid / 0.75),
            control2: CGPoint(x: reach, y: upperLid / 0.75))
        almond.addCurve(
            to: CGPoint(x: -halfWidth, y: 0),
            control1: CGPoint(x: reach, y: -lowerLid / 0.75),
            control2: CGPoint(x: -reach, y: -lowerLid / 0.75))
        almond.closeSubpath()

        // The upper lid is the taller one, so the almond's middle is above its corners. The pupil sits
        // on that middle, and the whole eye drops by the same amount to put the pupil on the origin.
        let rise = (upperLid - lowerLid) / 2

        context.saveGState()
        context.translateBy(x: 0, y: -rise)
        context.setFillColor(pupilBlue)
        context.fillEllipse(
            in: CGRect(x: -pupilRadius, y: rise - pupilRadius, width: pupilRadius * 2, height: pupilRadius * 2))
        context.addPath(almond)
        context.setStrokeColor(lidLight)
        context.setLineWidth(lidWidth)
        context.setLineJoin(.miter)
        context.setMiterLimit(4)
        context.strokePath()
        context.restoreGState()
    }
}

// MARK: - The icon

enum IconCanvas {
    /// Apple's icon grid: an 824-unit shape centred in 1024 units, with a transparent margin.
    case appleGrid
    /// Edge to edge and square, for a view that supplies its own clip shape (WelcomeView).
    case fullBleed
}

func renderIcon(pixels: Int, canvas: IconCanvas) -> CGContext {
    let context = makeContext(width: pixels, height: pixels, opaque: canvas == .fullBleed)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    context.setFillColor(ink)
    switch canvas {
    case .appleGrid:
        // SwiftUI only for the path: a continuous corner, like Apple's icon shape, which
        // CGPath(roundedRect:) is not. 185.4 is the radius in Apple's macOS icon template.
        // The margin is rounded down to whole pixels, or the small sizes get a grey half-covered edge
        // where the grid falls between pixels.
        let margin = (CGFloat(pixels) * 100 / 1024).rounded(.down) * 1024 / CGFloat(pixels)
        let side = 1024 - margin * 2
        let tile = RoundedRectangle(cornerRadius: side * 185.4 / 824, style: .continuous)
            .path(in: CGRect(x: margin, y: margin, width: side, height: side))
            .cgPath
        context.addPath(tile)
        context.fillPath()
        context.translateBy(x: 512, y: 512)
    case .fullBleed:
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        // Keep the eye the same share of the tile as it is on the grid.
        context.translateBy(x: 512, y: 512)
        context.scaleBy(x: 1024 / 824, y: 1024 / 824)
    }

    EyeShape.forIcon(pixels: pixels).draw(in: context)
    return context
}

// MARK: - The install window

/// Everything here is in points from the top left of the Finder window. `scripts/dmg-settings.py` has
/// to agree: its window size is this canvas, and its icon locations are the two centres below.
enum InstallWindow {
    static let size = CGSize(width: 660, height: 420)
    static let appIconCentre = CGPoint(x: 185, y: 236)
    static let applicationsCentre = CGPoint(x: 475, y: 236)
    static let headingBaseline: CGFloat = 96
    static let headingSize: CGFloat = 38
}

func loadFont(_ fileName: String, size: CGFloat) -> CTFont {
    // From the file, without registering it: nothing on this Mac can pick the font up as a side effect.
    let url = brandDir.appendingPathComponent(fileName) as CFURL
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
        let descriptor = descriptors.first
    else { fatalError("could not read \(fileName)") }
    return CTFontCreateWithFontDescriptor(descriptor, size, nil)
}

struct Cubic {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint

    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u
        let b = 3 * u * u * t
        let c = 3 * u * t * t
        let d = t * t * t
        return CGPoint(
            x: a * start.x + b * control1.x + c * control2.x + d * end.x,
            y: a * start.y + b * control1.y + c * control2.y + d * end.y)
    }

    func tangent(at t: CGFloat) -> CGVector {
        let u = 1 - t
        let a = 3 * u * u
        let b = 6 * u * t
        let c = 3 * t * t
        let x = a * (control1.x - start.x) + b * (control2.x - control1.x) + c * (end.x - control2.x)
        let y = a * (control1.y - start.y) + b * (control2.y - control1.y) + c * (end.y - control2.y)
        let length = max((x * x + y * y).squareRoot(), 0.0001)
        return CGVector(dx: x / length, dy: y / length)
    }
}

/// Fills a cubic as a pen line whose width follows `width(t)`, with round ends. A constant stroke is
/// what makes a drawn arrow look like a diagram; the swell is what makes it look drawn.
func inkStroke(_ curve: Cubic, in context: CGContext, width: (CGFloat) -> CGFloat) {
    let steps = 96
    var left: [CGPoint] = []
    var right: [CGPoint] = []
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps)
        let point = curve.point(at: t)
        let tangent = curve.tangent(at: t)
        let half = width(t) / 2
        left.append(CGPoint(x: point.x - tangent.dy * half, y: point.y + tangent.dx * half))
        right.append(CGPoint(x: point.x + tangent.dy * half, y: point.y - tangent.dx * half))
    }
    let outline = CGMutablePath()
    outline.addLines(between: left + right.reversed())
    outline.closeSubpath()
    context.addPath(outline)
    context.fillPath()
    // Filled apart from the outline: in one path the two wind against each other and cancel to a hole.
    for t in [CGFloat(0), 1] {
        let point = curve.point(at: t)
        let half = width(t) / 2
        context.fillEllipse(in: CGRect(x: point.x - half, y: point.y - half, width: half * 2, height: half * 2))
    }
}

func drawArrow(in context: CGContext, flip: (CGPoint) -> CGPoint) {
    // One stroke with a long rise and a short drop into the folder, so the top of the arc sits past
    // the middle, the way a hand throws it.
    let shaft = Cubic(
        start: flip(CGPoint(x: 254, y: 262)),
        control1: flip(CGPoint(x: 290, y: 228)),
        control2: flip(CGPoint(x: 358, y: 160)),
        end: flip(CGPoint(x: 395, y: 232)))

    context.setFillColor(arrowAmber)
    inkStroke(shaft, in: context) { t in
        2.6 + 2.2 * sin(.pi * pow(t, 0.8)) + 0.25 * sin(t * 11)
    }

    // Two barbs drawn back from the tip, unequal, because nobody draws them equal.
    let tip = shaft.end
    let inbound = shaft.tangent(at: 1)
    func barb(degrees: CGFloat, length: CGFloat, bow: CGFloat) -> Cubic {
        let angle = atan2(-inbound.dy, -inbound.dx) + degrees * .pi / 180
        let direction = CGVector(dx: cos(angle), dy: sin(angle))
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        func along(_ share: CGFloat, _ offset: CGFloat) -> CGPoint {
            CGPoint(
                x: tip.x + direction.dx * length * share + normal.dx * offset,
                y: tip.y + direction.dy * length * share + normal.dy * offset)
        }
        return Cubic(start: tip, control1: along(0.35, bow), control2: along(0.7, bow), end: along(1, 0))
    }
    inkStroke(barb(degrees: 36, length: 27, bow: 1.8), in: context) { t in 3.8 - 1.5 * t }
    inkStroke(barb(degrees: -44, length: 22, bow: -1.4), in: context) { t in 3.6 - 1.4 * t }
}

func renderInstallBackground(scale: Int) -> CGContext {
    let width = Int(InstallWindow.size.width) * scale
    let height = Int(InstallWindow.size.height) * scale
    let context = makeContext(width: width, height: height, opaque: true)
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    func flip(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: InstallWindow.size.height - point.y) }

    context.setFillColor(paper)
    context.fill(CGRect(origin: .zero, size: InstallWindow.size))

    let roman = loadFont("InstrumentSerif-Regular.ttf", size: InstallWindow.headingSize)
    let italic = loadFont("InstrumentSerif-Italic.ttf", size: InstallWindow.headingSize)
    let heading = NSMutableAttributedString()
    for (text, font) in [("To install, ", roman), ("drag", italic), (" Kannu to Applications", roman)] {
        heading.append(
            NSAttributedString(
                string: text,
                attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: font,
                    kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true,
                ]))
    }
    let line = CTLineCreateWithAttributedString(heading)
    let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    context.setFillColor(headingInk)
    context.setShouldSmoothFonts(false)
    context.textPosition = flip(
        CGPoint(x: (InstallWindow.size.width - lineWidth) / 2, y: InstallWindow.headingBaseline))
    CTLineDraw(line, context)

    drawArrow(in: context, flip: flip)
    return context
}

// MARK: - Output

print("Writing the app icon, logo2, kannu-logo.png, VolumeIcon.icns and the install window background")
let appIconSet = repoRoot.appendingPathComponent("Kannu/Assets.xcassets/AppIcon.appiconset")
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    writePNG(
        renderIcon(pixels: pixels, canvas: .appleGrid),
        to: appIconSet.appendingPathComponent("KannuIcon-\(pixels).png"))
}

writePNG(
    renderIcon(pixels: 1024, canvas: .fullBleed),
    to: repoRoot.appendingPathComponent("Kannu/Assets.xcassets/logo2.imageset/KannuIcon-1024.png"))
writePNG(
    renderIcon(pixels: 1024, canvas: .appleGrid),
    to: repoRoot.appendingPathComponent(".github/assets/kannu-logo.png"))

// The disk's own icon, in the only container Finder reads for a volume.
let iconSet = FileManager.default.temporaryDirectory
    .appendingPathComponent("KannuVolumeIcon-\(ProcessInfo.processInfo.processIdentifier).iconset")
try! FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconSet) }
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    writePNG(renderIcon(pixels: points * scale, canvas: .appleGrid), to: iconSet.appendingPathComponent(name))
}
let volumeIcon = brandDir.appendingPathComponent("VolumeIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconSet.path, "-o", volumeIcon.path]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

// dmgbuild finds the @2x file beside the 1x one and merges the pair. The DPI is what tells Finder the
// second image is the same window at twice the pixels, rather than a window twice the size.
writePNG(
    renderInstallBackground(scale: 1),
    to: brandDir.appendingPathComponent("dmg-background.png"),
    dpi: 72)
writePNG(
    renderInstallBackground(scale: 2),
    to: brandDir.appendingPathComponent("dmg-background@2x.png"),
    dpi: 144)
