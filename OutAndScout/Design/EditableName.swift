import SwiftUI

/// A name (project, scene, caption, file name) you can tap to change, wherever it appears.
/// Tapping opens the floating name bar at the top of the screen, so the keyboard never
/// covers what you're typing and nothing behind it moves.
struct EditableName: View {
    @Environment(ScoutStore.self) private var store

    let text: String
    let font: Font
    var color: Color = Sheet.text
    var lineLimit = 1
    /// Shown greyed when the text is empty, e.g. "untitled" for a caption.
    var emptyLabel = ""
    /// The bar's heading, e.g. "rename scene".
    var title = "Rename"
    /// Take the full width offered, so the whole row is the tap target, not just the words.
    var fillsWidth = false
    /// A small pencil after the words, like iOS, so it reads as editable.
    var pencil = false
    /// Bigger for the large titles.
    var pencilSize: CGFloat = 10
    /// Edit right where it is, at its own size, instead of in the floating bar. For big
    /// titles near the top, where the keyboard can't cover them.
    var inPlace = false
    let onRename: (String) -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField("", text: $draft)
                .font(font)
                .foregroundStyle(color)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(finish)
                .onChange(of: focused) { _, now in if !now { finish() } }
                .onAppear { focused = true }
                .overlay(alignment: .bottom) { Sheet.muted.frame(height: 1).offset(y: 2) }
        } else {
            label
        }
    }

    private func finish() {
        guard editing else { return }
        editing = false
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != text { onRename(name) }
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(text.isEmpty ? emptyLabel : text)
                .font(font)
                .foregroundStyle(text.isEmpty ? color.opacity(0.5) : color)
                .lineLimit(lineLimit)
            if pencil {
                Image(systemName: "pencil")
                    .font(.system(size: pencilSize))
                    .foregroundStyle(Sheet.muted)
                    .accessibilityHidden(true)
            }
        }
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if inPlace {
                    draft = text
                    editing = true
                } else {
                    store.rename = RenameRequest(title: title, text: text, commit: onRename)
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("tap to rename")
    }
}

/// What the floating name bar is editing.
struct RenameRequest: Identifiable {
    let id = UUID()
    var title: String
    var text: String
    var commit: (String) -> Void
}

/// The dark bar that drops in at the top of the screen to edit one name.
struct FloatingNameBar: View {
    @Environment(ScoutStore.self) private var store
    let request: RenameRequest

    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack {
                Text(request.title)
                    .font(.osDataSmall)
                    .foregroundStyle(Palette.nightMuted)
                Spacer()
                Button("Cancel") { store.rename = nil }
                    .font(.osSupport)
                    .foregroundStyle(Palette.nightMuted)
                    .buttonStyle(.plain)
                    .frame(minHeight: 36)
            }
            HStack(spacing: Space.xs) {
                TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Palette.nightMuted))
                    .font(.osRow)
                    .foregroundStyle(Palette.paper)
                    .tint(Palette.paper)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($typing)
                    .onSubmit(done)
                    .padding(.horizontal, Space.s)
                    .frame(height: ButtonHeight.chip)
                    .overlay(Capsule().strokeBorder(Palette.nightRule, lineWidth: 1))
                Chip(label: "Done") { done() }
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xs)
        .frame(maxWidth: 560)
        .background(Palette.ink, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.nightRule, lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, Space.xs)
        .task {
            text = request.text
            // Focus once the bar has slid in, or iOS drops the request.
            try? await Task.sleep(for: .milliseconds(150))
            typing = true
        }
    }

    /// What to type, from what's being edited: a caption, notes, a ratio, or a name.
    private var prompt: String {
        let t = request.title.lowercased()
        if t.contains("note") { return "Add some notes: access, power, sound…" }
        if t.contains("caption") { return "Describe the shot" }
        if t.contains("file") { return "File name" }
        if t.contains("scene") { return "Name this scene" }
        if t.contains("project") { return "Name this project" }
        return "Type a name"
    }

    private func done() {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Notes can be cleared; names and captions can't be left blank.
        let clearable = request.title.lowercased().contains("note")
        if (clearable || !name.isEmpty), name != request.text { request.commit(name) }
        store.rename = nil
    }
}

/// Sheets cover the app's own rename bar, so a sheet with names to edit shows it again
/// on top of itself (Elliot, 6 Oct 2026: renaming in Order and Names showed nothing).
struct RenameBarOverlay: ViewModifier {
    @Environment(ScoutStore.self) private var store

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            if let request = store.rename {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { store.rename = nil }
                    .transition(.opacity)
                FloatingNameBar(request: request)
                    .id(request.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: store.rename?.id)
        .onAppear { store.renameSheets += 1 }
        .onDisappear { store.renameSheets = max(0, store.renameSheets - 1) }
    }
}

extension View {
    func renameBar() -> some View { modifier(RenameBarOverlay()) }
}
