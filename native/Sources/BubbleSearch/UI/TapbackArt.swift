import AppKit

/// The original tapback artwork, loaded AT RUNTIME from the user's own macOS
/// via CoreUI — nothing of Apple's ships in our bundle.
///
/// The modern glossy glyphs (pink gradient heart, emoji-style thumbs) are the
/// FINAL FRAMES of the tapback animation sequences in Catalyst ChatKit
/// (heart_000…heart_108 etc.). We probe for the last frame so OS updates that
/// add/remove frames keep working. Monochrome IMSharedUI templates remain as
/// fallback, then SF Symbols.
enum TapbackArt {
    private static let chatKitCar =
        "/System/iOSSupport/System/Library/PrivateFrameworks/ChatKit.framework/Versions/A/Resources/Assets.car"
    private static let imSharedUICar =
        "/System/Library/PrivateFrameworks/IMSharedUI.framework/Versions/A/Resources/Assets.car"

    private static let sequenceBases: [Int: String] = [
        2000: "heart",
        2001: "thumbsup",
        2002: "thumbsdown",
        2003: "haha-ENG",
        2004: "exclamation",
        2005: "question",
    ]

    private static let templateNames: [Int: String] = [
        2000: "AckFunction-Heart-Template",
        2001: "AckFunction-ThumbsUp-Template",
        2002: "AckFunction-ThumbsDown-Template",
        2003: "AckFunction-HAHA-Template",
        2004: "AckFunction-Exclamation-Template",
        2005: "AckFunction-QuestionMark-Template",
    ]

    /// SF Symbol stand-ins, only used if the system catalogs are unavailable.
    static let sfFallbacks: [Int: String] = [
        2000: "heart.fill",
        2001: "hand.thumbsup.fill",
        2002: "hand.thumbsdown.fill",
        2003: "face.smiling.inverse",
        2004: "exclamationmark.2",
        2005: "questionmark",
    ]

    /// Colored, exactly-as-Messages glyphs (preferred).
    static let colored: [Int: NSImage] = {
        guard let catalog = CUICatalogHandle(path: chatKitCar) else { return [:] }
        var out: [Int: NSImage] = [:]
        for (kind, base) in sequenceBases {
            // Probe downward from a generous bound: first hit = last frame.
            for index in stride(from: 140, through: 0, by: -1) {
                let name = String(format: "%@_%03d", base, index)
                if let image = catalog.rasterizedImage(named: name, isTemplate: false) {
                    out[kind] = image
                    break
                }
            }
        }
        return out
    }()

    /// Monochrome templates (fallback, tinted at render time).
    static let templates: [Int: NSImage] = {
        guard let catalog = CUICatalogHandle(path: imSharedUICar) else { return [:] }
        var out: [Int: NSImage] = [:]
        for (kind, name) in templateNames {
            if let image = catalog.rasterizedImage(named: name, isTemplate: true) {
                out[kind] = image
            }
        }
        return out
    }()
}

/// Minimal CUICatalog wrapper (private CoreUI API via the ObjC runtime).
private final class CUICatalogHandle {
    private let catalog: NSObject
    private let imageFn: @convention(c) (AnyObject, Selector, NSString, CGFloat) -> AnyObject?
    private let imageSel = NSSelectorFromString("imageWithName:scaleFactor:")

    init?(path: String) {
        guard FileManager.default.fileExists(atPath: path),
              dlopen("/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI", RTLD_NOW) != nil,
              let catalogClass = NSClassFromString("CUICatalog") as? NSObject.Type
        else { return nil }

        let allocated = (catalogClass as AnyObject).perform(NSSelectorFromString("alloc")).takeUnretainedValue()
        let initSel = NSSelectorFromString("initWithURL:error:")
        guard let initMethod = class_getInstanceMethod(catalogClass, initSel) else { return nil }
        typealias InitFn = @convention(c) (AnyObject, Selector, NSURL, UnsafeMutablePointer<Unmanaged<NSError>?>?) -> Unmanaged<AnyObject>?
        let initFn = unsafeBitCast(method_getImplementation(initMethod), to: InitFn.self)
        var initError: Unmanaged<NSError>?
        guard let catalogRef = initFn(allocated, initSel, NSURL(fileURLWithPath: path), &initError) else {
            return nil
        }
        let catalog = catalogRef.takeRetainedValue() as! NSObject

        guard let imageMethod = class_getInstanceMethod(object_getClass(catalog), imageSel) else { return nil }
        typealias ImageFn = @convention(c) (AnyObject, Selector, NSString, CGFloat) -> AnyObject?
        self.imageFn = unsafeBitCast(method_getImplementation(imageMethod), to: ImageFn.self)
        self.catalog = catalog
    }

    /// Fetch and EAGERLY rasterize into a plain bitmap. The lazy CGImage that
    /// CoreUI returns decodes at render time and crashes (assertion in
    /// CA::Render::copy_image) once the catalog deallocates — rasterizing now,
    /// while it's alive, keeps CoreUI entirely out of the render path.
    func rasterizedImage(named name: String, isTemplate: Bool) -> NSImage? {
        guard let named = imageFn(catalog, imageSel, name as NSString, 2.0) as? NSObject else { return nil }
        let cgSel = NSSelectorFromString("image")
        guard let cgMethod = class_getInstanceMethod(object_getClass(named), cgSel) else { return nil }
        typealias CGFn = @convention(c) (AnyObject, Selector) -> Unmanaged<CGImage>?
        let cgFn = unsafeBitCast(method_getImplementation(cgMethod), to: CGFn.self)
        guard let cg = cgFn(named, cgSel)?.takeUnretainedValue() else { return nil }

        guard let context = CGContext(
            data: nil,
            width: cg.width,
            height: cg.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard var bitmap = context.makeImage() else { return nil }

        // The animation frames sit on a canvas with generous transparent
        // margins — crop to actual pixels so the glyph can fill the bubble.
        if let cropped = Self.croppedToAlpha(bitmap, context: context) {
            bitmap = cropped
        }

        let image = NSImage(cgImage: bitmap, size: NSSize(width: CGFloat(bitmap.width) / 2, height: CGFloat(bitmap.height) / 2))
        image.isTemplate = isTemplate
        return image
    }

    private static func croppedToAlpha(_ image: CGImage, context: CGContext) -> CGImage? {
        guard let data = context.data else { return nil }
        let width = context.width
        let height = context.height
        let bytesPerRow = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width {
                let alpha = pixels[row + x * 4 + 3] // RGBA
                if alpha > 8 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
}
