import AppKit
import AVFoundation
import ImageIO

/// Downscaled thumbnail generation, off the main thread. HEIC/JPEG/PNG via
/// ImageIO; video poster frames via AVFoundation.
enum Thumbnailer {
    static func make(path: String, isVideo: Bool, maxPixel: CGFloat = 512) -> NSImage? {
        isVideo ? videoThumb(path: path, maxPixel: maxPixel) : imageThumb(path: path, maxPixel: maxPixel)
    }

    private static func imageThumb(path: String, maxPixel: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static func videoThumb(path: String, maxPixel: CGFloat) -> NSImage? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        guard let cg = try? generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
