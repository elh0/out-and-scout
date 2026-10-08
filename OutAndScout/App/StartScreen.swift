import SwiftUI

/// The start screen, B2 (Elliot, round 4, 8 Oct 2026): your recces on the left, newest first,
/// with "+ New project" on top; the picked one previewed on the right before you open it,
/// with its scenes, the next good light and Open camera / Shots / Export. Upright, the
/// preview sits above the list. Covers the viewfinder while the camera starts underneath.
struct StartScreen: View {
    @Environment(ScoutStore.self) private var store
    let done: () -> Void

    @State private var picked: UUID?
    @State private var naming = false
    @State private var newName = ""
    @FocusState private var typing: Bool

    var body: some View {
        GeometryReader { geo in
            let portrait = geo.size.height > geo.size.width
            ZStack(alignment: .topLeading) {
                Sheet.bg.ignoresSafeArea()
                if portrait {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Wordmark(size: 20).padding(.top, Space.l)
                        if let p = selected { preview(p, compact: true) }
                        list
                    }
                    .padding(.horizontal, Space.l)
                } else {
                    HStack(alignment: .top, spacing: Space.xl) {
                        VStack(alignment: .leading, spacing: Space.m) {
                            Wordmark(size: 20).padding(.top, 6)
                            list
                        }
                        .frame(width: min(280, geo.size.width * 0.36))
                        if let p = selected { preview(p, compact: false) }
                    }
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.m)
                }
            }
        }
        .foregroundStyle(Sheet.text)
    }

    private var projects: [Project] {
        store.projects.sorted { $0.createdAt > $1.createdAt }
    }

    private var selected: Project? {
        let id = picked ?? store.currentProjectID
        return store.projects.first { $0.id == id } ?? projects.first
    }

    // MARK: List

    private var list: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.snappy(duration: 0.2)) { naming.toggle(); typing = naming } } label: {
                    HStack(spacing: 10) {
                        Text("+")
                            .font(Fonts.mono(12))
                            .frame(width: 26, height: 22)
                            .overlay(Capsule().strokeBorder(Outline.line, lineWidth: 1))
                        Text("NEW PROJECT").font(Fonts.mono(10)).tracking(0.6)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(OPressRing())

                if naming {
                    HStack(spacing: 8) {
                        TextField("", text: $newName, prompt: Text("Name this recce").foregroundStyle(Sheet.muted))
                            .font(.osSans(16))
                            .focused($typing)
                            .submitLabel(.go)
                            .onSubmit(create)
                            .padding(.bottom, 4)
                            .overlay(alignment: .bottom) { Outline.line.frame(height: 1.5) }
                        OPill(label: "Start", on: true, size: .small, caps: true, action: create)
                    }
                    .padding(.bottom, 10)
                    .transition(.opacity)
                }

                ForEach(projects) { p in row(p) }
            }
        }
    }

    private func row(_ p: Project) -> some View {
        let on = p.id == selected?.id
        let count = p.scenes.reduce(0) { $0 + $1.shots.count }
        return Button { withAnimation(.snappy(duration: 0.2)) { picked = p.id } } label: {
            HStack(spacing: 12) {
                still(of: p)
                    .frame(width: 48, height: 27)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.osSans(13)).lineLimit(1)
                    Text(Self.date(p.createdAt).uppercased()).font(Fonts.mono(8)).tracking(0.6).foregroundStyle(Sheet.muted)
                }
                Spacer(minLength: 4)
                Text("\(count)").font(Fonts.mono(9)).foregroundStyle(Sheet.muted)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(on ? Sheet.text.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .top) { if !on { Sheet.rule.frame(height: 1).padding(.horizontal, 10) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(OPressRing())
        .padding(.horizontal, -10)
        .accessibilityLabel("\(p.name), \(ShotListView.shots(count))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Preview card

    private func preview(_ p: Project, compact: Bool) -> some View {
        let shots = p.scenes.flatMap(\.shots)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.m) {
                still(of: p)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: compact ? 140 : 250)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.name).font(.osSans(compact ? 17 : 20)).lineLimit(2)
                    Text(Self.date(p.createdAt).uppercased()).font(Fonts.mono(9)).tracking(0.6)
                        .foregroundStyle(Sheet.muted).padding(.top, 4)
                    if !compact { details(p, shots: shots) }
                }
                Spacer(minLength: 0)
            }
            if compact { details(p, shots: shots) }
            Spacer(minLength: Space.s)
            HStack(alignment: .bottom) {
                if !compact {
                    // As many of the last stills as fit beside the buttons (none on an SE).
                    ViewThatFits(in: .horizontal) {
                        thumbs(shots.suffix(3))
                        thumbs(shots.suffix(2))
                        thumbs(shots.suffix(1))
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    OPill(label: "Open camera", on: true, caps: true) { open(p) }
                    OPill(label: "Shots · \(shots.count)", caps: true) { open(p) { store.showingShotList = true } }
                    if !shots.isEmpty {
                        OPill(label: "Export", caps: true) { open(p) { store.showingShotList = true; store.showingExport = true } }
                    }
                }
                .layoutPriority(1)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity, alignment: .topLeading)
        .background(Outline.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Outline.line, lineWidth: 1.5))
    }

    private func thumbs(_ shots: ArraySlice<Shot>) -> some View {
        HStack(spacing: 6) {
            ForEach(shots) { s in
                ShotThumb(shot: s).frame(width: 79, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
    }

    private func details(_ p: Project, shots: [Shot]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SCENES").font(Fonts.mono(8)).tracking(0.6).foregroundStyle(Sheet.muted).padding(.top, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(p.scenes) { sc in
                        OPill(label: sc.name, size: .small) { open(p, scene: sc.id) }
                    }
                }
            }
            Text("NEXT GOOD LIGHT").font(Fonts.mono(8)).tracking(0.6).foregroundStyle(Sheet.muted).padding(.top, 8)
            Text(nextLight(shots)).font(.osSans(12)).padding(.top, 3).lineLimit(2)
        }
    }

    /// "1A · 17:58–18:38, golden hour, ¾ back", from the last shot's spot and heading; else
    /// today's golden hour here.
    private func nextLight(_ shots: [Shot]) -> String {
        if let s = shots.last(where: { $0.bearing != nil && $0.location != nil }), let b = s.bearing, let loc = s.location {
            let day = SunCalculator.day(containing: Date(), latitude: loc.latitude, longitude: loc.longitude)
            if let best = LightRead.best(day: day, heading: b) {
                return "\(s.number) · \(Format.time(best.start))–\(Format.time(best.end)), \(best.why)"
            }
        }
        let loc = shots.last(where: { $0.location != nil })?.location
        let day = SunCalculator.day(containing: Date(), latitude: loc?.latitude ?? 51.5, longitude: loc?.longitude ?? -0.12)
        if let g = day.goldenWindows.last(where: { $0.upperBound > Date() }) ?? day.goldenWindows.last {
            return "Golden hour \(Format.time(g.lowerBound))–\(Format.time(g.upperBound))"
        }
        return "Check the sun path in the camera"
    }

    @ViewBuilder private func still(of p: Project) -> some View {
        if let last = p.scenes.flatMap(\.shots).last {
            ShotThumb(shot: last)
        } else {
            Color(hex: 0x1F1F1D)
        }
    }

    // MARK: Actions

    private func open(_ p: Project, scene: UUID? = nil, then: (() -> Void)? = nil) {
        store.select(project: p.id, scene: scene)
        done()
        then?()
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = store.projects.filter { $0.name.hasPrefix("Untitled") }.count + 1
        store.addProject(named: name.isEmpty ? "Untitled \(n)" : name)
        newName = ""
        naming = false
        done()
    }

    static func date(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
