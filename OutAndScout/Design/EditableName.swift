import SwiftUI

/// A project or scene name (or a shot caption) you can tap to rename in place, wherever it appears.
/// Return or tapping away saves; an empty name keeps the old one.
struct EditableName: View {
    let text: String
    let font: Font
    var color: Color = Palette.ink
    var lineLimit = 1
    /// Shown greyed when the text is empty, e.g. "untitled" for a caption.
    var emptyLabel = ""
    let onRename: (String) -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField("name", text: $draft)
                .font(font)
                .foregroundStyle(color)
                .tint(color)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .onAppear { focused = true }
                .frame(minWidth: 80)
                .overlay(alignment: .bottom) {
                    color.opacity(0.4).frame(height: 1).offset(y: 2)
                }
        } else {
            Text(text.isEmpty ? emptyLabel : text)
                .font(font)
                .foregroundStyle(text.isEmpty ? color.opacity(0.5) : color)
                .lineLimit(lineLimit)
                .contentShape(Rectangle())
                .onTapGesture {
                    draft = text
                    editing = true
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("tap to rename")
        }
    }

    private func commit() {
        guard editing else { return }
        editing = false
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != text { onRename(name) }
    }
}
