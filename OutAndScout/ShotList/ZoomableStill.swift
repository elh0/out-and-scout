import SwiftUI
import UIKit

/// One still in the full-screen viewer that you can pinch into, like Photos (18 Nov 2026):
/// pinch or double-tap to zoom, drag to look around, double-tap to go back. A sharper copy
/// loads once you zoom in. A single tap calls `onTap` (the viewer closes only when not zoomed).
struct ZoomableStill: UIViewRepresentable {
    let shot: Shot
    @Binding var zoomed: Bool
    /// Changes when Blur faces is flipped or a face is fixed, so the picture redraws.
    var blurKey: String = ""
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> StillScrollView {
        let v = StillScrollView()
        v.onZoomChange = { [weak coordinator = context.coordinator] scale in
            coordinator?.zoomChanged(scale)
        }
        v.onSingleTap = { [weak coordinator = context.coordinator] in coordinator?.parent.onTap() }
        context.coordinator.view = v
        context.coordinator.load(shot)
        return v
    }

    func updateUIView(_ v: StillScrollView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.shotKey != shot.photoFile.map({ "\($0)\(shot.aspect.value)\(blurKey)" }) {
            context.coordinator.load(shot)
        }
    }

    static func dismantleUIView(_ v: StillScrollView, coordinator: Coordinator) {
        coordinator.task?.cancel()
        v.setImage(nil)
    }

    @MainActor
    final class Coordinator {
        var parent: ZoomableStill
        weak var view: StillScrollView?
        var task: Task<Void, Never>?
        var shotKey: String?
        private var sharp = false

        init(_ parent: ZoomableStill) { self.parent = parent }

        func load(_ shot: Shot) {
            task?.cancel()
            sharp = false
            shotKey = shot.photoFile.map { "\($0)\(shot.aspect.value)\(parent.blurKey)" }
            let blur = BlurPrefs.isOn
            // With Blur faces on, never flash the unblurred picture first.
            if !blur, let hit = ThumbCache.cached(shot, .screen) {
                view?.setImage(Self.cropped(hit, to: shot))
            }
            task = Task { [weak self] in
                guard let image = await ThumbCache.load(shot, .screen), !Task.isCancelled else { return }
                if blur {
                    let id = shot.id
                    let soft = await Task.detached(priority: .userInitiated) { BlurFaces.prepared(image, shot: id) }.value
                    guard !Task.isCancelled else { return }
                    self?.view?.setImage(Self.cropped(soft, to: shot), keepZoom: true)
                    BlurPrefs.shared.found += 1
                } else {
                    self?.view?.setImage(Self.cropped(image, to: shot), keepZoom: true)
                }
            }
        }

        func zoomChanged(_ scale: CGFloat) {
            let isZoomed = scale > 1.01
            if parent.zoomed != isZoomed { parent.zoomed = isZoomed }
            // Past 1.5x the 2400 px copy starts to soften: read the still near full size,
            // once, without keeping it in the shared cache.
            guard scale > 1.5, !sharp else { return }
            sharp = true
            let shot = parent.shot
            task = Task { [weak self] in
                let big = await Task.detached(priority: .userInitiated) {
                    ThumbCache.downsampled(for: shot, maxPixel: 4400).map { BlurFaces.prepared($0, shot: shot.id) }
                }.value
                guard let big, !Task.isCancelled else { return }
                self?.view?.setImage(Self.cropped(big, to: shot), keepZoom: true)
            }
        }

        /// The picture cropped to the shot's frame lines, centred (a "Full" shot stays whole).
        nonisolated static func cropped(_ image: UIImage, to shot: Shot) -> UIImage {
            guard !shot.aspect.isFull, shot.aspect.value > 0, let cg = image.cgImage else { return image }
            let w = CGFloat(cg.width), h = CGFloat(cg.height), target = shot.aspect.value
            var crop = CGSize(width: w, height: h)
            if w / h > target { crop.width = (h * target).rounded(.down) } else { crop.height = (w / target).rounded(.down) }
            let rect = CGRect(x: ((w - crop.width) / 2).rounded(.down), y: ((h - crop.height) / 2).rounded(.down),
                              width: crop.width, height: crop.height)
            return cg.cropping(to: rect).map { UIImage(cgImage: $0, scale: image.scale, orientation: image.imageOrientation) } ?? image
        }
    }
}

/// A scroll view that holds one picture fitted to the screen and keeps it centred while
/// zoomed, the way Photos does.
final class StillScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    var onZoomChange: ((CGFloat) -> Void)?
    var onSingleTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        decelerationRate = .fast
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)

        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        single.require(toFail: double)
        addGestureRecognizer(single)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Swaps the picture. `keepZoom` keeps where you are (a sharper copy of the same still).
    func setImage(_ image: UIImage?, keepZoom: Bool = false) {
        let sameShape = imageView.image.map { old in
            image.map { abs(old.size.width / old.size.height - $0.size.width / $0.size.height) < 0.001 } ?? false
        } ?? false
        imageView.image = image
        if keepZoom, sameShape { return }
        zoomScale = 1
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard zoomScale <= 1.001 else { centre(); return }
        // Fit the picture inside the page at 1x.
        let bounds = self.bounds.size
        guard let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0 else {
            imageView.frame = CGRect(origin: .zero, size: bounds)
            contentSize = bounds
            return
        }
        let s = min(bounds.width / size.width, bounds.height / size.height)
        let fit = CGSize(width: size.width * s, height: size.height * s)
        if imageView.frame.size != fit {
            imageView.frame = CGRect(origin: .zero, size: fit)
            contentSize = fit
        }
        centre()
    }

    /// Keeps the picture in the middle when it's smaller than the screen in either direction.
    private func centre() {
        let b = bounds.size, c = contentSize
        let x = max(0, (b.width - c.width) / 2), y = max(0, (b.height - c.height) / 2)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centre()
        onZoomChange?(zoomScale)
    }

    @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
        if zoomScale > 1.01 {
            setZoomScale(1, animated: true)
        } else {
            // Zoom 2.5x on the point you tapped.
            let p = g.location(in: imageView)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func singleTapped() { onSingleTap?() }
}
