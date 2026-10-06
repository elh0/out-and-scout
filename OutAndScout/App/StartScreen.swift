import SwiftUI

/// After the opening: one tap to carry on where you were, or start a new project. Covers the
/// viewfinder on solid ink while the camera starts underneath.
struct StartScreen: View {
    @Environment(ScoutStore.self) private var store
    let done: () -> Void

    var body: some View {
        GeometryReader { geo in
            let portrait = geo.size.height > geo.size.width
            // The prototype's 56pt margin is from the screen edge; the safe area already gives ~47.
            let side: CGFloat = portrait ? 24 : Space.xs
            ZStack(alignment: .topLeading) {
                // Solid ink: the viewfinder's controls must not show through and collide
                // with the choices. The camera is still starting underneath.
                Sheet.bg.ignoresSafeArea()

                HStack(alignment: .firstTextBaseline) {
                    Wordmark(size: 17)
                    Spacer()
                    Button {
                        store.panel = .projects
                        done()
                    } label: {
                        Text("All projects")
                            .font(.osRow)
                            .foregroundStyle(Sheet.text)
                            .underline(color: Sheet.muted)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, side)
                .padding(.top, portrait ? 56 : 14)

                VStack(spacing: 0) {
                    Spacer()
                    Sheet.text.opacity(0.22).frame(height: 1)
                    if portrait {
                        VStack(alignment: .leading, spacing: 0) {
                            continueChoice
                            Sheet.text.opacity(0.22).frame(height: 1)
                            newChoice
                        }
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            continueChoice
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1.4)
                            Sheet.text.opacity(0.22).frame(width: 1)
                            newChoice
                                .padding(.leading, Space.xl)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, side)
                .padding(.bottom, portrait ? 48 : 28)
            }
        }
        .foregroundStyle(Sheet.text)
    }

    private var continueChoice: some View {
        let project = store.currentProject
        let scene = store.currentScene
        return choice(
            kicker: "Continue",
            title: project.name,
            sub: "\(scene.name) · \(ShotListView.shots(scene.shots.count))",
            action: done
        )
    }

    private var newChoice: some View {
        choice(kicker: "Start", title: "New project", sub: "Name it later. Opens straight to the camera.") {
            let n = store.projects.filter { $0.name.hasPrefix("Untitled") }.count + 1
            store.addProject(named: "Untitled \(n)")
            store.toast = "New project. Rename it under Edit in Projects."
            done()
        }
    }

    private func choice(kicker: String, title: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Caps(text: kicker).foregroundStyle(Sheet.muted)
                Text(title)
                    .font(Fonts.mono(24))
                    .tracking(-0.4)
                    .lineLimit(1)
                Text(sub)
                    .font(.osRow)
                    .foregroundStyle(Sheet.muted)
                    .lineLimit(2)
            }
            .padding(.top, 18)
            .padding(.bottom, 10)
            .padding(.trailing, Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
