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
