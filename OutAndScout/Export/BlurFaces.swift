import CoreImage
import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// Blur faces (Out & Scout 1.1, Elliot 18 Nov 2026): finds faces in a recce still and softens
/// them with a feathered oval that follows each face, not a hard circle. Easy to correct:
/// tap a face to unblur it, tap an empty spot to add one; the corrections are kept per still.
/// Originals are never changed; only exports (PDF, JPEG, Photos, Selects) and the on-screen
/// preview use the blurred copy.
///
/// Regions are normalised 0…1 with a TOP-LEFT origin (the way SwiftUI lays out a photo),
/// always relative to the upright, uncropped still.
enum BlurFaces {

    // MARK: Corrections

    struct Corrections: Codable, Equatable {
        /// Detected faces the user tapped off. A detected face is off when its centre is inside one.
        var removed: [CGRect] = []
        /// Spots the user tapped on.
        var added: [CGRect] = []
        var isEmpty: Bool { removed.isEmpty && added.isEmpty }
    }

    // MARK: Finding faces

    /// Faces in an upright image, grown a little so hair, ears and chin are covered.
    /// Runs Vision at full resolution so small faces in wide shots are found too. Call off the main thread.
    static func detect(_ image: CGImage) -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) } catch { return [] }
        return (request.results ?? []).filter { $0.confidence > 0.25 }.map { face in
            let b = face.boundingBox // Vision: bottom-left origin
            var r = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            // Vision's box is tight on the features: widen for ears, lift for hair, drop for chin.
            r = r.insetBy(dx: -r.width * 0.22, dy: -r.height * 0.30)
            r.origin.y -= r.height * 0.05
            return r
        }
    }

    /// What gets blurred: detected faces the user hasn't turned off, plus the spots they added.
    static func regions(detected: [CGRect], corrections c: Corrections) -> [CGRect] {
        let kept = detected.filter { face in
            !c.removed.contains { $0.contains(CGPoint(x: face.midX, y: face.midY)) }
        }
        return kept + c.added
    }

    /// Fix mode: one tap at a normalised point.
    /// On an added spot → removes it. On a blurred face → unblurs it. On a face that was
    /// unblurred → blurs it again. Anywhere else → adds a face-sized spot there.
    /// `imageSize` is the upright still's pixel size, so a new spot comes out face-shaped.
    static func toggle(at p: CGPoint, detected: [CGRect], corrections: Corrections, imageSize: CGSize) -> Corrections {
        var c = corrections
        if let i = c.added.lastIndex(where: { $0.contains(p) }) {
            c.added.remove(at: i)
            return c
        }
        if let face = regions(detected: detected, corrections: c).first(where: { $0.contains(p) }) {
            c.removed.append(face)
            return c
        }
        if let i = c.removed.lastIndex(where: { $0.contains(p) }) {
            c.removed.remove(at: i)
            return c
        }
        c.added.append(spot(at: p, near: detected, imageSize: imageSize))
        return c
    }

    /// A new spot the size of the typical face in this still (or 9% of the width if none).
    private static func spot(at p: CGPoint, near faces: [CGRect], imageSize: CGSize) -> CGRect {
        let widths = faces.map(\.width).sorted()
        let w = widths.isEmpty ? 0.09 : widths[widths.count / 2]
        // Faces are about 1.3x taller than wide in pixels; convert to normalised height.
        let aspect = imageSize.height > 0 ? imageSize.width / imageSize.height : 1
        let h = w * 1.3 * aspect
        return CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
    }

    // MARK: Blurring

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The still with every region softened behind a feathered oval. Returns the input when
    /// there's nothing to blur. Call off the main thread for full-size stills.
    static func apply(to image: CGImage, regions: [CGRect]) -> CGImage {
        guard !regions.isEmpty else { return image }
        let source = CIImage(cgImage: image)
        let extent = source.extent
        let W = extent.width, H = extent.height

        // Mask: white where blurred, fading to clear at each oval's edge.
        var mask = CIImage(color: .clear).cropped(to: extent)
        var sizes: [CGFloat] = []
        for r in regions {
            let px = CGRect(x: r.minX * W, y: (1 - r.maxY) * H, width: r.width * W, height: r.height * H) // Core Image: bottom-left
            guard px.width > 1, px.height > 1 else { continue }
            sizes.append(min(px.width, px.height))
            let radius = max(px.width, px.height) / 2
            let g = CIFilter.radialGradient()
            g.center = .zero
            g.radius0 = Float(radius * 0.58)   // solid core
            g.radius1 = Float(radius)          // soft feather out to the edge
            g.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
            g.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
            guard let round = g.outputImage?.cropped(to: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)) else { continue }
            // Squash the circle into the face's oval, then move it onto the face.
            let oval = round
                .transformed(by: CGAffineTransform(scaleX: px.width / (radius * 2), y: px.height / (radius * 2)))
                .transformed(by: CGAffineTransform(translationX: px.midX, y: px.midY))
            mask = oval.composited(over: mask)
        }
        guard !sizes.isEmpty else { return image }

        // Blur strength follows the faces: strong enough that nobody is recognisable,
        // soft enough to read as a photo, not a censor block.
        let median = sizes.sorted()[sizes.count / 2]
        let sigma = max(10, median * 0.16)
        let blurred = source.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: extent)

        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = blurred
        blend.backgroundImage = source
        blend.maskImage = mask
        guard let out = blend.outputImage,
              let cg = context.createCGImage(out, from: extent, format: .RGBA8, colorSpace: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
        else { return image }
        return cg
    }

    /// Convenience for UIImage (any orientation): draws it upright, finds faces, applies the
    /// corrections and blurs. Pass `detected` if you already have it, to skip Vision.
    static func apply(to image: UIImage, corrections: Corrections = .init(), detected: [CGRect]? = nil) -> UIImage {
        guard let upright = upright(image) else { return image }
        let faces = detected ?? detect(upright)
        let out = apply(to: upright, regions: regions(detected: faces, corrections: corrections))
        return UIImage(cgImage: out, scale: image.scale, orientation: .up)
    }

    /// The image's pixels with its orientation applied.
    static func upright(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }
}

/// Corrections per still, kept beside the projects in their own file, so the project
/// model and Elliot's existing projects are untouched. Thread-safe: exports read it from
/// background tasks.
final class BlurCorrectionsStore: @unchecked Sendable {
    static let shared = BlurCorrectionsStore()

    private let lock = NSLock()
    private var all: [UUID: BlurFaces.Corrections] = [:]
    /// Faces found per still, cached for the session (Vision is the slow part).
    private var found: [UUID: [CGRect]] = [:]

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("blur-corrections.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([UUID: BlurFaces.Corrections].self, from: data) {
            all = saved
        }
    }

    func corrections(for shot: UUID) -> BlurFaces.Corrections {
        lock.withLock { all[shot] ?? .init() }
    }

    func set(_ c: BlurFaces.Corrections, for shot: UUID) {
        let data: Data? = lock.withLock {
            all[shot] = c.isEmpty ? nil : c
            return try? JSONEncoder().encode(all)
        }
        if let data { try? data.write(to: url, options: .atomic) }
    }

    func cachedFaces(for shot: UUID) -> [CGRect]? { lock.withLock { found[shot] } }
    func cache(_ faces: [CGRect], for shot: UUID) { lock.withLock { found[shot] = faces } }
}

/// The one Blur faces switch. The viewfinder ··· menu, the shot card, Selects, the viewer and
/// Export → Include all show and flip this same switch.
@MainActor @Observable final class BlurPrefs {
    static let shared = BlurPrefs()
    static let key = "blur.faces"

    var on: Bool {
        didSet { UserDefaults.standard.set(on, forKey: Self.key) }
    }
    /// Bumped when faces are found or a Fix tap changes a still, so views redraw.
    var version = 0
    /// Bumped when a still's faces have been found, so Fix rings can draw.
    var found = 0

    private init() { on = UserDefaults.standard.bool(forKey: Self.key) }

    /// Safe from any thread (exports run in the background).
    nonisolated static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }
}

extension BlurFaces {
    /// The faces to soften in this shot's still: found once (cached), then corrected.
    static func regions(shot: UUID, image: CGImage) -> [CGRect] {
        let store = BlurCorrectionsStore.shared
        let faces = store.cachedFaces(for: shot) ?? {
            let f = detect(image)
            store.cache(f, for: shot)
            return f
        }()
        return regions(detected: faces, corrections: store.corrections(for: shot))
    }

    /// The image blurred where the shot's faces are, when Blur faces is on; else as is.
    /// Works on any size of the still (regions are normalised). Call off the main thread.
    static func prepared(_ image: UIImage, shot: UUID) -> UIImage {
        guard BlurPrefs.isOn, let up = upright(image) else { return image }
        let out = apply(to: up, regions: regions(shot: shot, image: up))
        return UIImage(cgImage: out, scale: image.scale, orientation: .up)
    }

    /// Same for an upright CGImage (the full-size JPEG writer).
    static func prepared(_ image: CGImage, shot: UUID) -> CGImage {
        guard BlurPrefs.isOn else { return image }
        return apply(to: image, regions: regions(shot: shot, image: image))
    }
}

// MARK: - The switch and Fix (1.1 Paper)

/// "BLUR FACES" with a tick box: the same switch everywhere it appears.
struct BlurSwitch: View {
    @State private var prefs = BlurPrefs.shared

    var body: some View {
        Button { prefs.on.toggle() } label: {
            HStack(spacing: 6) {
                TickBox(on: prefs.on)
                Text("BLUR FACES").font(Fonts.mono(9)).tracking(0.6)
                    .foregroundStyle(prefs.on ? Sheet.text : Sheet.muted)
                    .fixedSize()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("blur faces")
        .accessibilityAddTraits(prefs.on ? .isSelected : [])
    }
}

/// Fix mode over the viewer's picture: a dashed orange ring on each blurred face, a faint one
/// on faces turned off. Tap a ring to unblur that face (or blur it again); tap an empty spot to
/// add one. Corrections are kept per still; the original is never changed.
struct BlurFixOverlay: View {
    let shot: Shot
    @State private var prefs = BlurPrefs.shared

    /// The upright still's width over height, and the part of it on screen (the frame lines).
    private var imageAspect: Double { shot.stillAspect ?? AspectRatio.viewfinderValue }
    private var shownAspect: Double { shot.aspect.isFull || shot.aspect.value <= 0 ? imageAspect : shot.aspect.value }
    private var window: CGRect {
        let ia = imageAspect, t = shownAspect
        let wf = ia > t ? t / ia : 1, hf = ia > t ? 1 : ia / t
        return CGRect(x: (1 - wf) / 2, y: (1 - hf) / 2, width: wf, height: hf)
    }

    var body: some View {
        GeometryReader { geo in
            let fit = fitted(in: geo.size)
            let win = window
            let store = BlurCorrectionsStore.shared
            let detected = store.cachedFaces(for: shot.id) ?? []
            let c = store.corrections(for: shot.id)
            let on = BlurFaces.regions(detected: detected, corrections: c)
            let off = detected.filter { f in !on.contains(f) }
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        let n = CGPoint(x: win.minX + (tap.location.x - fit.minX) / fit.width * win.width,
                                        y: win.minY + (tap.location.y - fit.minY) / fit.height * win.height)
                        guard (0...1).contains(n.x), (0...1).contains(n.y) else { return }
                        let next = BlurFaces.toggle(at: n, detected: detected, corrections: c,
                                                    imageSize: CGSize(width: imageAspect, height: 1))
                        store.set(next, for: shot.id)
                        prefs.version += 1
                    })
                ForEach(Array(off.enumerated()), id: \.offset) { _, r in
                    ring(r, fit: fit, win: win).stroke(Sheet.muted.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .allowsHitTesting(false)
                }
                ForEach(Array(on.enumerated()), id: \.offset) { _, r in
                    ring(r, fit: fit, win: win).stroke(Palette.sun, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .allowsHitTesting(false)
                }
                Text("TAP A RING TO UNBLUR · TAP A FACE TO ADD")
                    .font(Fonts.mono(9)).tracking(0.6)
                    .foregroundStyle(Palette.onPicture)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Palette.onPictureInk.opacity(0.6))
                    .position(x: fit.midX, y: fit.minY + 16)
                    .allowsHitTesting(false)
            }
            .id("\(prefs.found)-\(prefs.version)")
        }
    }

    /// The picture's rect in the viewer: aspect-fit and centred.
    private func fitted(in size: CGSize) -> CGRect {
        let t = CGFloat(shownAspect)
        var w = size.width, h = size.width / t
        if h > size.height { h = size.height; w = h * t }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func ring(_ r: CGRect, fit: CGRect, win: CGRect) -> Path {
        let x = fit.minX + (r.minX - win.minX) / win.width * fit.width
        let y = fit.minY + (r.minY - win.minY) / win.height * fit.height
        return Path(ellipseIn: CGRect(x: x, y: y, width: r.width / win.width * fit.width, height: r.height / win.height * fit.height))
    }
}
