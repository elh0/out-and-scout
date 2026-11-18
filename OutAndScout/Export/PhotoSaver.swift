import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

/// Saves stills to the Photos library, cropped to their frame lines (a "Full" shot keeps
/// the whole frame). Asks for add-only access, so the app never sees the library.
///
/// Memory-safe (18 Nov 2026): it used to hold every full-size still in memory at once,
/// on the main thread, which got the app killed on big projects. Now each still is written
/// to a JPEG file one at a time, off the main thread, and Photos reads the files.
enum PhotoSaver {
    enum Failure: Error { case notAllowed, nothingToSave }

    /// Returns how many stills were saved.
    @discardableResult
    static func save(_ shots: [Shot]) async throws -> Int {
        guard shots.contains(where: { $0.photoFile != nil }) else { throw Failure.nothingToSave }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.notAllowed }

        let folder = StillWriter.freshFolder("photos-save")
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = await StillWriter.writeAll(shots, into: folder, names: { shot, _ in shot.id.uuidString })
        guard !files.isEmpty else { throw Failure.nothingToSave }

        // A few at a time, so one huge change never piles up.
        for batch in stride(from: 0, to: files.count, by: 20).map({ Array(files[$0..<min($0 + 20, files.count)]) }) {
            try await PHPhotoLibrary.shared().performChanges {
                for url in batch {
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: options)
                }
            }
        }
        return files.count
    }
}

/// Writes stills as plain JPEG files, cropped to their frame lines, one at a time so
/// memory stays flat however many there are. Used by Save to Photos and the Selects page.
enum StillWriter {
    /// An empty folder in tmp for one export.
    static func freshFolder(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes each shot to `folder` off the main thread; returns the files made, in order.
    /// `names` gives the file name (no extension) for each shot and its position.
    static func writeAll(_ shots: [Shot], into folder: URL,
                         names: (Shot, Int) -> String,
                         progress: (@MainActor (Int) -> Void)? = nil) async -> [URL] {
        var made: [URL] = []
        for (i, shot) in shots.enumerated() {
            if Task.isCancelled { break }
            let url = folder.appendingPathComponent(names(shot, i)).appendingPathExtension("jpg")
            let ok = await Task.detached(priority: .userInitiated) {
                autoreleasepool { StillWriter.write(shot, to: url) }
            }.value
            if ok { made.append(url) }
            if let progress { await progress(i + 1) }
        }
        return made
    }

    /// The still, upright, cropped to the shot's ratio and centred, at full resolution,
    /// written straight to a JPEG file. Returns false if there's no still or it can't be read.
    static func write(_ shot: Shot, to url: URL) -> Bool {
        guard let src = ScoutStore.photoURL(for: shot),
              let source = CGImageSourceCreateWithURL(src as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return false }

        // Decode once at full size with the rotation applied, so the crop is upright.
        let upright: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, upright as CFDictionary) else { return false }
        // Blur faces (1.1) before the crop, so regions line up with the whole still.
        let full = BlurFaces.prepared(decoded, shot: shot.id)

        var image = full
        let target = shot.aspect.value
        if !shot.aspect.isFull, target > 0 {
            let size = CGSize(width: full.width, height: full.height)
            var crop = size
            if size.width / size.height > target { crop.width = (size.height * target).rounded(.down) }
            else { crop.height = (size.width / target).rounded(.down) }
            let rect = CGRect(x: ((size.width - crop.width) / 2).rounded(.down),
                              y: ((size.height - crop.height) / 2).rounded(.down),
                              width: crop.width, height: crop.height)
            if let cropped = full.cropping(to: rect) { image = cropped }
        }

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        var meta: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        // Keep the taken date so Photos and Finder sort them properly.
        if let exif = props[kCGImagePropertyExifDictionary] { meta[kCGImagePropertyExifDictionary] = exif }
        if let gps = props[kCGImagePropertyGPSDictionary] { meta[kCGImagePropertyGPSDictionary] = gps }
        CGImageDestinationAddImage(dest, image, meta as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }
}
