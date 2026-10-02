import Photos
import UIKit

/// Saves stills to the Photos library, cropped to their frame lines (a "Full" shot keeps
/// the whole frame). Asks for add-only access, so the app never sees the library.
enum PhotoSaver {
    enum Failure: Error { case notAllowed, nothingToSave }

    /// Returns how many stills were saved.
    @discardableResult
    static func save(_ shots: [Shot]) async throws -> Int {
        let images = shots.compactMap(framed)
        guard !images.isEmpty else { throw Failure.nothingToSave }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.notAllowed }
        try await PHPhotoLibrary.shared().performChanges {
            for image in images { PHAssetChangeRequest.creationRequestForAsset(from: image) }
        }
        return images.count
    }

    /// The still cropped to the shot's ratio, centred, at full resolution.
    static func framed(_ shot: Shot) -> UIImage? {
        guard let full = ThumbCache.full(for: shot) else { return nil }
        guard !shot.aspect.isFull, shot.aspect.value > 0 else { return full }
        let size = full.size
        let target = shot.aspect.value
        var crop = size
        if size.width / size.height > target {
            crop.width = size.height * target
        } else {
            crop.height = size.width / target
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = full.scale
        return UIGraphicsImageRenderer(size: crop, format: format).image { _ in
            full.draw(at: CGPoint(x: (crop.width - size.width) / 2, y: (crop.height - size.height) / 2))
        }
    }
}
