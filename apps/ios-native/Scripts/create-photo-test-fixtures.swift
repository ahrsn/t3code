import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Generated images for native picker tests.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let types: [UTType] = CommandLine.arguments.contains("--heic") ? [.png, .jpeg, .heic] : [.png, .jpeg]
for (index, type) in types.enumerated() {
    let context = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: index == 0 ? 0.28 : 0.10, green: index == 1 ? 0.5 : 0.18, blue: index == 2 ? 0.5 : 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
    let name = "T3 Photo Fixture \(index + 1)." + type.preferredFilenameExtension!
    let url = directory.appendingPathComponent(name)
    guard let image = context.makeImage(), let output = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
        throw NSError(domain: "PhotoFixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create " + name])
    }
    CGImageDestinationAddImage(output, image, nil)
    guard CGImageDestinationFinalize(output) else {
        throw NSError(domain: "PhotoFixtures", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot encode " + name])
    }
    print(name)
}

if CommandLine.arguments.contains("--oversized") {
    let width = 2000, height = 1900
    var pixels = Data(count: width * height * 4), state: UInt64 = 0x123456789abcdef
    pixels.withUnsafeMutableBytes { bytes in
        let pixels = bytes.bindMemory(to: UInt8.self)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            pixels[index] = UInt8(truncatingIfNeeded: state)
            pixels[index + 1] = UInt8(truncatingIfNeeded: state >> 8)
            pixels[index + 2] = UInt8(truncatingIfNeeded: state >> 16); pixels[index + 3] = 255
        }
    }
    let provider = CGDataProvider(data: pixels as CFData)!
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let file = directory.appendingPathComponent("T3 Photo Oversized.png")
    let output = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(output, image, nil)
    guard CGImageDestinationFinalize(output), (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 10 * 1024 * 1024 else {
        throw NSError(domain: "PhotoFixtures", code: 3, userInfo: [NSLocalizedDescriptionKey: "Oversized fixture did not exceed the image limit"])
    }
    print(file.lastPathComponent)
}
