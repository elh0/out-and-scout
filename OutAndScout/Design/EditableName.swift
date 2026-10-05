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
    let onRename: (String) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(text.isEmpty ? emptyLabel : text)
                .font(font)
                .foregroundStyle(text.isEmpty ? color.opacity(0.5) : color)
                .lineLimit(lineLimit)
            if pencil {
                Image(systemName: "pencil")
                    .font(.system(size: 10))
                    .foregroundStyle(Sheet.muted)
                    .accessibilityHidden(true)
            }
        }
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                store.rename = RenameRequest(title: title, text: text, commit: onRename)
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

    private func done() {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != request.text { request.commit(name) }
        store.rename = nil
    }
}
