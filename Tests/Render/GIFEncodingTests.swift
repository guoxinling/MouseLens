import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MouseLens

final class GIFEncodingTests: XCTestCase {
    func testEncodeGIFWritesRequestedFrameCountAndDelay() throws {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gif")

        let frames = [
            makeSolidFrame(color: .init(red: 1, green: 0, blue: 0, alpha: 1), size: CGSize(width: 32, height: 18)),
            makeSolidFrame(color: .init(red: 0, green: 0, blue: 1, alpha: 1), size: CGSize(width: 32, height: 18))
        ]

        try GIFFrameEncoder.encode(
            frames: frames,
            frameDelay: 1.0 / 15.0,
            destinationURL: destinationURL
        )

        guard let source = CGImageSourceCreateWithURL(destinationURL as CFURL, nil) else {
            return XCTFail("Failed to read GIF")
        }

        XCTAssertEqual(CGImageSourceGetCount(source), 2)
        let fileProperties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let fileGIFProperties = fileProperties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let loopCount = fileGIFProperties?[kCGImagePropertyGIFLoopCount] as? Int
        let delay = gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let expectedDelay = (1.0 / 15.0 * 100).rounded() / 100
        XCTAssertEqual(loopCount, 0)
        XCTAssertNotNil(delay)
        XCTAssertEqual(delay ?? 0, expectedDelay, accuracy: 0.0001)
    }

    func testEncodeGIFWritesGlobalColorMapHints() throws {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gif")

        let frames = [
            makeGradientFrame(size: CGSize(width: 64, height: 36)),
            makeGradientFrame(size: CGSize(width: 64, height: 36), phase: 0.18)
        ]

        try GIFFrameEncoder.encode(
            frames: frames,
            frameDelay: 1.0 / 15.0,
            destinationURL: destinationURL
        )

        guard let source = CGImageSourceCreateWithURL(destinationURL as CFURL, nil) else {
            return XCTFail("Failed to read GIF")
        }

        let fileProperties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let fileGIFProperties = fileProperties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        XCTAssertEqual(fileGIFProperties?[kCGImagePropertyGIFHasGlobalColorMap] as? Bool, true)
    }
}

private func makeSolidFrame(color: CGColor, size: CGSize) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(color)
    context.fill(CGRect(origin: .zero, size: size))
    return context.makeImage()!
}

private func makeGradientFrame(size: CGSize, phase: CGFloat = 0) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    for x in 0..<Int(size.width) {
        let t = (CGFloat(x) / max(size.width - 1, 1) + phase).truncatingRemainder(dividingBy: 1)
        context.setFillColor(CGColor(red: t, green: 0.3 + 0.4 * t, blue: 1 - t, alpha: 1))
        context.fill(CGRect(x: CGFloat(x), y: 0, width: 1, height: size.height))
    }
    return context.makeImage()!
}
