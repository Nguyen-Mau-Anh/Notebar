import AppKit
import Foundation

/// What happens to an image once `NSTextView` has already turned a paste or
/// a drag into an `NSTextAttachment` (spec §6.2c) — `NSTextView` does that
/// part without any work on our part; this is the two consequences that are
/// our work. Lives in `NotebarStore`, not `NotebarCore`, for the same reason
/// `NoteRTF` does: this needs AppKit (`NSImage`, `NSTextAttachment`), which
/// `NotebarCore` must never import (spec section 3, rule 1).
public enum NoteImageEmbedding {
    /// An embedded image whose longest edge exceeds this many pixels is
    /// downscaled before it round-trips into `body_rtf`'s RTFD (spec
    /// §6.2c deliverable 3). A modern screenshot is 6-8MB at full size and
    /// gains nothing rendered in a 340pt panel, and every one of those
    /// megabytes lives in the note's row forever. The named constant this
    /// spec asks for lives here rather than the app target's `Tokens` enum
    /// because this file — and the math that uses this value — must stay
    /// usable from a plain `NSImage`/`NSTextStorage` with no SwiftUI, which
    /// `Tokens` depends on.
    public static let maxEmbeddedDimensionPixels: CGFloat = 2000

    /// Scans every image attachment in `textView`'s text storage, downscales
    /// any whose longest edge exceeds `maxEmbeddedDimensionPixels`, and caps
    /// each one's displayed width at the text container's width (spec
    /// §6.2c deliverable 2: "must scale to fit, not overflow or get
    /// clipped"), preserving aspect ratio. Called from `NoteEditorView`'s
    /// `textDidChange`, which fires after both a paste and a completed
    /// drag — there is no separate hook for either, so this is the one
    /// place both paths get normalized before the body is saved.
    ///
    /// Idempotent and cheap to call on every keystroke: an attachment
    /// already downscaled and already sized to fit produces the same
    /// `bounds`/`image` it already has, so `didChange` stays `false` and
    /// nothing is re-written.
    public static func normalizeAttachments(in textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let padding = (textView.textContainer?.lineFragmentPadding ?? 0) * 2
        let containerWidth = (textView.textContainer?.size.width ?? .greatestFiniteMagnitude) - padding
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var didChange = false

        textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { value, _, _ in
            guard let attachment = value as? NSTextAttachment, let image = attachment.image else { return }

            let downscaled = downscaledIfNeeded(image)
            if downscaled !== image {
                attachment.image = downscaled
                didChange = true
            }

            let fitted = NSRect(origin: .zero, size: fittedSize(for: attachment.image?.size ?? downscaled.size, maxWidth: containerWidth))
            if attachment.bounds != fitted {
                attachment.bounds = fitted
                didChange = true
            }
        }

        // Mutating `attachment.image`/`.bounds` in place doesn't itself tell
        // the layout system anything changed — those are plain properties on
        // an object the text storage merely points to, not an edit to the
        // text storage's own attribute runs. This is the documented way to
        // force a relayout after exactly that kind of in-place mutation.
        if didChange {
            textStorage.edited(.editedAttributes, range: fullRange, changeInLength: 0)
        }
    }

    /// The scaling math on its own, independent of any live text view —
    /// what the downscaling half of deliverable 3 actually is. `internal`
    /// visibility would hide it from `NotebarStoreTests`; exposed publicly
    /// so it can be asserted on directly.
    public static func downscaledIfNeeded(_ image: NSImage) -> NSImage {
        let pixelSize = image.pixelSize
        let longestEdge = max(pixelSize.width, pixelSize.height)
        guard longestEdge > maxEmbeddedDimensionPixels, longestEdge > 0 else { return image }
        let scale = maxEmbeddedDimensionPixels / longestEdge
        return image.resized(to: NSSize(width: pixelSize.width * scale, height: pixelSize.height * scale))
    }

    private static func fittedSize(for imageSize: NSSize, maxWidth: CGFloat) -> NSSize {
        guard imageSize.width > maxWidth, maxWidth > 0, imageSize.width > 0 else { return imageSize }
        let scale = maxWidth / imageSize.width
        return NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

extension NSImage {
    /// The image's actual pixel dimensions, as opposed to `size` — which for
    /// an image with non-standard DPI metadata can differ from its pixel
    /// grid. Downscaling decisions (spec §6.2c) care about pixels, not
    /// points, since that's what the 2000px limit and file size are about.
    var pixelSize: NSSize {
        guard let rep = representations.first else { return size }
        return NSSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
    }

    /// Draws the image into a freshly, explicitly sized bitmap — simple and
    /// sufficient per spec §6.2c ("`NSImage` drawing into a correctly sized
    /// bitmap is enough"), with no third-party image library needed for a
    /// resize this infrequent. Builds the destination `NSBitmapImageRep`
    /// directly with `pixelsWide`/`pixelsHigh` set to the requested size,
    /// rather than `lockFocus()` on an `NSImage`, so the result's pixel
    /// dimensions are exactly what was asked for regardless of the current
    /// display's backing scale factor.
    func resized(to newSize: NSSize) -> NSImage {
        guard newSize.width > 0, newSize.height > 0,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(newSize.width.rounded()),
                pixelsHigh: Int(newSize.height.rounded()),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              )
        else { return self }

        bitmap.size = newSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        let resized = NSImage(size: newSize)
        resized.addRepresentation(bitmap)
        return resized
    }
}
