import SwiftUI

/// Light card that rises over the Viewfinder. Radius 24, paper, no shadow.
/// While the keyboard is up the card jumps to the top so the field stays in view;
/// nothing behind it moves.
struct SheetCard<Content: View>: View {
    let eyebrow: String
    var maxWidth: CGFloat = 620
    @ViewBuilder let content: Content

    @State private var keyboardUp = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(eyebrow)
                .font(.osDataSmall)
                .foregroundStyle(Palette.graphite)
            content
        }
        .padding(Space.l)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: keyboardUp ? .top : .bottom)
        .padding(.vertical, Space.xs)
        .ignoresSafeArea(.keyboard)
        .animation(.snappy(duration: 0.25), value: keyboardUp)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
    }
}

/// Single-line text field in the light sheets.
struct SheetField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.graphite))
            .font(.osRow)
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .onSubmit(onSubmit)
            .padding(.horizontal, Space.s)
            .frame(height: 44)
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.rule, lineWidth: 1))
    }
}

// MARK: - 04 Caption card

/// Pops up after the shutter with three suggested captions.
struct CaptionCard: View {
    @Environment(ScoutStore.self) private var store
    @State private var pick = 0
    @State private var custom = ""
    @FocusState private var typing: Bool

    var body: some View {
        if let p = store.pending {
            SheetCard(eyebrow: typing ? "Your own caption · \(p.number)" : "Suggested caption") {
                // While typing, only the field and save stay, so the card fits above the keyboard.
                // The field itself never moves between layouts, so it keeps focus.
                if !typing {
                    HStack(alignment: .top, spacing: Space.m) {
                        Group {
                            if let data = p.photo, let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Color(hex: 0x2B2B28)
                            }
                        }
                        .frame(width: 168, height: 168 / max(store.aspect.value, 0.6))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.readout, style: .continuous))

                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("\(p.number) · \(Format.mm(p.lensMM))mm · \(Format.time(p.plannedTime)) · \(p.light.label)")
                                .font(.osNum)
                                .foregroundStyle(Palette.graphite)

                            ForEach(Array(p.suggestions.enumerated()), id: \.offset) { i, s in
                                Button {
                                    pick = i
                                    custom = ""
                                } label: {
                                    HStack {
                                        Text(s.text).font(.osRow).lineLimit(1)
                                        Spacer(minLength: Space.xs)
                                        Text(s.tag).font(.osDataSmall).foregroundStyle(Palette.graphite)
                                    }
                                    .padding(.horizontal, Space.s)
                                    .frame(minHeight: 40)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.card)
                                            .strokeBorder(pick == i && custom.isEmpty ? Palette.ink : Palette.rule, lineWidth: 1)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                HStack(spacing: Space.xs) {
                    SheetField(placeholder: "Your own caption", text: $custom) { save(p) }
                        .focused($typing)
                    if typing {
                        Button("Save \(p.number)") { save(p) }
                            .buttonStyle(PillButtonStyle(kind: .secondary))
                    }
                }

                if !typing {
                    HStack(spacing: Space.xs) {
                        Button("Retake") { store.pending = nil }
                            .buttonStyle(PillButtonStyle(kind: .secondary))
                        Button("Save \(p.number)") { save(p) }
                            .buttonStyle(PillButtonStyle(kind: .primary))
                    }
                }
            }
        }
    }

    private func save(_ p: PendingShot) {
        let typed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggested = p.suggestions.isEmpty ? "" : p.suggestions[min(pick, p.suggestions.count - 1)].text
        let caption = typed.isEmpty ? suggested : typed
        typing = false
        store.commitPending(caption: caption)
    }
}

// MARK: - 07 Location permission prompt

/// Asked the first time a scene is added. Explains why before iOS asks.
struct LocationPermissionCard: View {
    @Environment(ScoutStore.self) private var store
    @Environment(LocationService.self) private var location

    var body: some View {
        SheetCard(eyebrow: "Location permission", maxWidth: 520) {
            Text("Use your precise location?")
                .font(Font.osTitle)

            VStack(alignment: .leading, spacing: Space.xs) {
                reason("01", "Names each scene after the street you're on.")
                reason("02", "Tags every shot with where it was taken, for the shot list and map.")
                reason("03", "Works out the sun for that exact spot.")
            }

            // Agreed with Elliot, 1 Oct 2026. True while the app has no server (street names come from
            // Apple's on-device-requested geocoder). Revisit if live links ship.
            Text("Saved only on your phone. We never upload them; you choose when to share a shot list.")
                .font(.osSupport)
                .foregroundStyle(Palette.graphite)

            HStack(spacing: Space.xs) {
                Button("Allow Precise") { choose(.precise) }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                Button("Approximate") { choose(.approximate) }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button("Not Now") { choose(.notNow) }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            }
        }
    }

    private func reason(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(n).font(.osData).foregroundStyle(Palette.graphite)
            Text(text).font(.osSupport)
        }
    }

    private func choose(_ choice: LocationChoice) {
        store.locationChoice = choice
        store.askingLocation = false
        location.request(choice)
        if store.locationAskAddsScene { store.addScene() }
    }
}

// MARK: - Name-this-scene card

/// A slim dark bar at the top of the Viewfinder. One tap on a suggestion names the scene;
/// typing is there if you want it, and the bar stays above the keyboard.
struct NameSceneCard: View {
    @Environment(ScoutStore.self) private var store
    @Environment(LocationService.self) private var location
    @State private var text = ""
    @State private var suggestions: [String] = []
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack {
                Text(store.namingProject ? "Rename Project" : store.namingByTyping ? "Rename Scene" : "Name This Scene")
                    .font(.osDataSmall)
                    .foregroundStyle(Palette.nightMuted)
                Spacer()
                if store.namingByTyping {
                    Button("Cancel") { store.namingSceneID = nil }
                        .font(.osSupport)
                        .foregroundStyle(Palette.nightMuted)
                        .buttonStyle(.plain)
                        .frame(minHeight: 36)
                } else {
                    // Cancel undoes "+ Scene"; Keep keeps it with its default name.
                    Button("Cancel") { store.cancelNewScene() }
                        .font(.osSupport)
                        .foregroundStyle(Palette.nightMuted)
                        .buttonStyle(.plain)
                        .frame(minHeight: 36)
                        .padding(.trailing, Space.s)
                    Button("Keep \"\(store.currentScene.name)\"") { store.namingSceneID = nil }
                        .font(.osSupport)
                        .foregroundStyle(Palette.paper)
                        .buttonStyle(.plain)
                        .frame(minHeight: 36)
                }
            }

            HStack(spacing: Space.xs) {
                TextField("", text: $text, prompt: Text("Type a name").foregroundStyle(Palette.nightMuted))
                    .font(.osRow)
                    .foregroundStyle(Palette.paper)
                    .tint(Palette.paper)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($typing)
                    .onSubmit(done)
                    .padding(.horizontal, Space.s)
                    .frame(width: 200, height: ButtonHeight.chip)
                    .overlay(Capsule().strokeBorder(Palette.nightRule, lineWidth: 1))

                if typing || store.namingProject {
                    Chip(label: "Done") { done() }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.xxs) {
                            ForEach(suggestions + ["studio", "interior", "field"], id: \.self) { s in
                                Chip(label: s, mono: false) { pick(s) }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xs)
        .frame(maxWidth: 640)
        .background(Palette.ink, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.nightRule, lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, Space.xs)
        .ignoresSafeArea(.keyboard)
        .task {
            if store.namingByTyping {
                text = store.namingProject ? store.currentProject.name : store.currentScene.name
                // Focus once the bar has slid in, or iOS drops the request.
                try? await Task.sleep(for: .milliseconds(150))
                typing = true
            }
            suggestions = await location.nameSuggestions()
        }
    }

    private func pick(_ name: String) {
        if let id = store.namingSceneID { store.renameScene(id, to: name) }
        store.namingSceneID = nil
    }

    private func done() {
        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            if store.namingProject {
                store.renameProject(store.currentProjectID, to: text)
            } else if let id = store.namingSceneID {
                store.renameScene(id, to: text)
            }
        }
        store.namingSceneID = nil
    }
}

// MARK: - Custom aspect card

struct CustomAspectCard: View {
    @Environment(ScoutStore.self) private var store
    @State private var text = ""
    @State private var error = ""

    var body: some View {
        SheetCard(eyebrow: "Custom aspect · saved to your kit", maxWidth: 480) {
            HStack(spacing: Space.xxs) {
                ForEach(AspectRatio.customPresets) { a in
                    Chip(label: a.label, onDark: false) { add(a) }
                }
            }
            HStack(spacing: Space.xs) {
                SheetField(placeholder: "Aspect ratio, e.g. 2.2 or 4:3", text: $text, onSubmit: addTyped)
                Button("Add", action: addTyped)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button("Close") { store.showingCustomAspect = false }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            }
            if !error.isEmpty {
                Text(error).font(.osSupport).foregroundStyle(Palette.graphite)
            }
        }
    }

    private func addTyped() {
        guard let a = AspectRatio.parse(text) else {
            error = "That's not a ratio we can frame. Try 2.2 or 4:3."
            return
        }
        add(a)
    }

    private func add(_ a: AspectRatio) {
        store.addCustomAspect(a)
        store.showingCustomAspect = false
    }
}
