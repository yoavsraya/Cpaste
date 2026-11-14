import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import CpasteCore

func makeStore() throws -> ClipStore {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cpaste-tests-\(UUID().uuidString)")
    return try ClipStore(directory: directory)
}

func pngData(width: Int = 800, height: Int = 600) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

func fileCount(in directory: URL) -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
}

func classify(_ items: [String: Data]) -> Capture? {
    classify(types: Set(items.keys), read: { items[$0] })
}
