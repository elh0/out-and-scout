import Foundation
import Observation

/// What the shutter produced, waiting on the Caption card.
struct PendingShot: Identifiable {
    var id = UUID()
    var number: String
    var photo: Data?
    var suggestions: [CaptionSuggestion]
    var lensMM: Double
    var plannedTime: Date
    var sun: SunPosition
    var light: LightPhase
    var bearing: Double?
    var location: ShotLocation?
    var stillAspect: Double = AspectRatio.viewfinderValue
}

enum LocationChoice: String, Codable {
    case precise, approximate, notNow
}

struct Overlays: Codable, Hashable {
    var sunPath = true
    var grid = false
    var level = false
}

enum Panel: Equatable {
    case projects
    case kit
}

/// App state. One store, injected into the environment at the root.
@MainActor
@Observable
final class ScoutStore {
    // Persisted
    var projects: [Project]
    var currentProjectID: UUID
    var currentSceneID: UUID
    var kit: Kit
    var lensMM: Double
    var aspect: AspectRatio
    var customAspects: [AspectRatio]
    var overlays: Overlays
    var locationChoice: LocationChoice?

    // Transient UI state
    /// Minutes after local midnight the sun timeline is set to. nil means "now".
    var plannedMinutes: Double?
    var panel: Panel?
    var showingShotList = false
    var showingExport = false
    var showingCustomAspect = false
    var askingLocation = false
    /// The location card was opened by "+ scene", so a scene is added once it's answered.
    var locationAskAddsScene = true
    /// The scene the Name-this-scene card is open for.
    var namingSceneID: UUID?
    /// True when the bar was opened by tapping the scene name, so it starts with the keyboard up.
    var namingByTyping = false
    /// True when the name bar is renaming the current project rather than a scene.
    var namingProject = false
    var pending: PendingShot?
    /// A name being edited in the floating name bar.
    var rename: RenameRequest?
    var toast: String?
    /// The shot just taken; the Viewfinder shows its caption for a few seconds with an edit link.
    var justSaved: UUID?

    private let fileURL: URL

    init(fileURL: URL = ScoutStore.defaultURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let snap = try? JSONDecoder.scout.decode(Snapshot.self, from: data),
           let project = snap.projects.first(where: { $0.id == snap.currentProjectID }) ?? snap.projects.first,
           let scene = project.scenes.first(where: { $0.id == snap.currentSceneID }) ?? project.scenes.first {
            projects = snap.projects
            currentProjectID = project.id
            currentSceneID = scene.id
            kit = snap.kit
            lensMM = snap.lensMM
            aspect = snap.aspect
            customAspects = snap.customAspects
            overlays = snap.overlays
            locationChoice = snap.locationChoice
        } else {
            // If a saved file exists but won't load, keep a copy rather than overwrite it.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let backup = fileURL.deletingPathExtension()
                    .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: fileURL, to: backup)
            }
            // No setup before first use: a project and a scene are ready to pin into.
            let scene = ScoutScene(name: "Scene 1", note: Format.shortDate(Date()))
            let project = Project(name: "First Recce", kind: "", scenes: [scene])
            projects = [project]
            currentProjectID = project.id
            currentSceneID = scene.id
            kit = .default
            lensMM = 35
            aspect = .scope
            customAspects = []
            overlays = Overlays()
            locationChoice = nil
        }
        fixOldLowercaseNames()
    }

    // MARK: Lookups

    var currentProject: Project {
        projects.first { $0.id == currentProjectID } ?? projects[0]
    }

    var currentScene: ScoutScene {
        currentProject.scenes.first { $0.id == currentSceneID } ?? currentProject.scenes[0]
    }

    /// "5A": the next setup number in the current scene.
    /// One past the highest number used, so deleting a shot never reuses its number.
    var nextShotNumber: String {
        let used = currentScene.shots.compactMap { Int($0.number.prefix { $0.isNumber }) }
        return "\((used.max() ?? 0) + 1)A"
    }

    var aspectStrip: [AspectRatio] { AspectRatio.strip + customAspects }

    var focalLengths: [Double] { kit.lenses.focals }

    func plannedDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        guard let minutes = plannedMinutes else { return now }
        return calendar.startOfDay(for: now).addingTimeInterval(minutes * 60)
    }

    // MARK: Lens

    func stepLens(_ delta: Int) {
        let focals = focalLengths
        guard !focals.isEmpty else { return }
        let i = focals.firstIndex { $0 >= lensMM } ?? focals.count - 1
        let next = min(max(i + delta, 0), focals.count - 1)
        lensMM = focals[next]
        save()
    }

    func setKit(_ newKit: Kit) {
        kit = newKit
        if !newKit.lenses.focals.contains(lensMM) {
            // Keep roughly the same framing: nearest focal in the new set.
            lensMM = newKit.lenses.focals.min { abs($0 - lensMM) < abs($1 - lensMM) } ?? lensMM
        }
        if newKit.lenses.isAnamorphic { aspect = .scope }
        save()
    }

    func setAspect(_ a: AspectRatio) {
        aspect = a
        save()
    }

    func addCustomAspect(_ a: AspectRatio) {
        if !aspectStrip.contains(where: { abs($0.value - a.value) < 0.005 }) {
            customAspects.append(a)
        }
        aspect = a
        save()
    }

    func toggle(_ keyPath: WritableKeyPath<Overlays, Bool>) {
        overlays[keyPath: keyPath].toggle()
        save()
    }

    // MARK: Projects and scenes

    func select(project: UUID, scene: UUID? = nil) {
        guard let p = projects.first(where: { $0.id == project }) else { return }
        currentProjectID = p.id
        currentSceneID = scene ?? p.scenes.first?.id ?? currentSceneID
        save()
    }

    /// Adds a scene to the current project. The first time, ask about location first.
    func requestNewScene() {
        if locationChoice == nil {
            locationAskAddsScene = true
            askingLocation = true
        } else {
            addScene()
        }
    }

    @discardableResult
    func addScene(named name: String? = nil, location: ShotLocation? = nil) -> UUID {
        let index = currentProject.scenes.count + 1
        sceneBeforeNew = currentSceneID
        let scene = ScoutScene(
            name: name ?? location?.label ?? "Scene \(index)",
            note: Format.shortDate(Date()),
            location: location
        )
        updateProject(currentProjectID) { $0.scenes.append(scene) }
        currentSceneID = scene.id
        namingByTyping = false
        namingProject = false
        namingSceneID = scene.id
        save()
        return scene.id
    }

    /// Names and captions from before the switch to proper capitals were saved all
    /// lowercase ("first recce", "queen's road"). Once, give those a capital: each word for
    /// project and scene names, the first letter for captions. Anything with a capital
    /// already is left as typed.
    private func fixOldLowercaseNames() {
        let key = "casingFixed"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        func isAllLower(_ t: String) -> Bool { t == t.lowercased() && t != t.uppercased() }
        func words(_ t: String) -> String {
            t.split(separator: " ", omittingEmptySubsequences: false)
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
        func first(_ t: String) -> String { t.prefix(1).uppercased() + t.dropFirst() }
        for p in projects.indices {
            if isAllLower(projects[p].name) { projects[p].name = words(projects[p].name) }
            for s in projects[p].scenes.indices {
                if isAllLower(projects[p].scenes[s].name) { projects[p].scenes[s].name = words(projects[p].scenes[s].name) }
                for i in projects[p].scenes[s].shots.indices where isAllLower(projects[p].scenes[s].shots[i].caption) {
                    projects[p].scenes[s].shots[i].caption = first(projects[p].scenes[s].shots[i].caption)
                }
            }
        }
        save()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// The scene that was showing before "+ Scene", so Cancel can go back to it.
    private var sceneBeforeNew: UUID?

    /// Cancel on the name bar after "+ Scene": take the new scene away again (only while
    /// it's still empty) and go back to the scene you were on.
    func cancelNewScene() {
        guard let id = namingSceneID else { return }
        namingSceneID = nil
        guard let scene = currentProject.scenes.first(where: { $0.id == id }), scene.shots.isEmpty else { return }
        let back = sceneBeforeNew
        deleteScene(id)
        if let back, currentProject.scenes.contains(where: { $0.id == back }) { currentSceneID = back; save() }
        sceneBeforeNew = nil
    }

    /// Opens the name bar on the current scene, ready to type.
    func startRenamingCurrentScene() {
        namingByTyping = true
        namingProject = false
        namingSceneID = currentSceneID
    }

    /// Opens the same name bar on the current project.
    func startRenamingCurrentProject() {
        namingByTyping = true
        namingProject = true
        namingSceneID = currentSceneID
    }

    func renameScene(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateScene(id) { $0.name = trimmed }
        save()
    }

    func renameProject(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateProject(id) { $0.name = trimmed }
        save()
    }

    /// Asked once, on launch, if it's never been answered: projects made from the Projects
    /// panel skip "+ scene", so otherwise no shot would ever carry a location.
    func askForLocationIfNeverAsked() {
        guard locationChoice == nil, !askingLocation else { return }
        locationAskAddsScene = false
        askingLocation = true
    }

    func addProject(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let scene = ScoutScene(name: "Scene 1", note: Format.shortDate(Date()))
        let project = Project(name: trimmed, kind: "", scenes: [scene])
        projects.append(project)
        currentProjectID = project.id
        currentSceneID = scene.id
        save()
    }

    // MARK: Shots

    func commitPending(caption: String) {
        guard let p = pending else { return }
        addShot(p, caption: caption)
        pending = nil
    }

    /// Saves a shot to the current scene straight away (the shutter doesn't wait on a caption).
    func addShot(_ p: PendingShot, caption: String) {
        var photoFile: String?
        if let data = p.photo {
            let name = "\(p.id.uuidString).heic"
            do {
                try FileManager.default.createDirectory(at: Self.shotsFolder, withIntermediateDirectories: true)
                try data.write(to: Self.shotsFolder.appendingPathComponent(name), options: .atomic)
                photoFile = name
            } catch {
                toast = "Couldn't save the still"
            }
        }
        let shot = Shot(
            id: p.id,
            number: p.number,
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
            lensMM: p.lensMM,
            aspect: aspect.isFull ? .full(p.stillAspect) : aspect,
            cameraName: kit.camera.name,
            lensSeries: kit.lenses.name,
            plannedTime: p.plannedTime,
            capturedAt: Date(),
            sunAzimuth: p.sun.azimuth,
            sunElevation: p.sun.elevation,
            light: p.light,
            bearing: p.bearing,
            location: p.location,
            photoFile: photoFile,
            stillAspect: p.stillAspect
        )
        updateScene(currentSceneID) { $0.shots.append(shot) }
        toast = "Saved \(shot.number)"
        save()
    }

    /// Fills in what arrives after the shutter: the auto caption (only if the shot is still
    /// untitled, so a caption typed in the meantime wins) and the place name.
    func fillIn(_ id: UUID, caption: String?, location: ShotLocation?) {
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for p in projects.indices {
            for s in projects[p].scenes.indices {
                if let i = projects[p].scenes[s].shots.firstIndex(where: { $0.id == id }) {
                    if !trimmed.isEmpty, projects[p].scenes[s].shots[i].caption.isEmpty {
                        projects[p].scenes[s].shots[i].caption = trimmed
                    }
                    if let location, projects[p].scenes[s].shots[i].location == nil {
                        projects[p].scenes[s].shots[i].location = location
                    }
                }
            }
        }
        save()
    }

    /// Reorders the current project's scenes (the Export panel's drag handles); the PDF and
    /// CSV follow this order.
    func moveScenes(from source: IndexSet, to destination: Int) {
        guard let p = projects.firstIndex(where: { $0.id == currentProjectID }) else { return }
        projects[p].scenes.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Reorders the shots in one scene (the Export panel's drag handles). Numbers stay with
    /// their shots; the PDF and CSV follow the new order.
    func moveShots(in sceneID: UUID, from source: IndexSet, to destination: Int) {
        updateScene(sceneID) { $0.shots.move(fromOffsets: source, toOffset: destination) }
        save()
    }

    func shot(_ id: UUID) -> Shot? {
        for project in projects {
            for scene in project.scenes {
                if let shot = scene.shots.first(where: { $0.id == id }) { return shot }
            }
        }
        return nil
    }

    func setNotes(_ id: UUID, to notes: String) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        for p in projects.indices {
            for s in projects[p].scenes.indices {
                if let i = projects[p].scenes[s].shots.firstIndex(where: { $0.id == id }) {
                    projects[p].scenes[s].shots[i].notes = trimmed.isEmpty ? nil : trimmed
                }
            }
        }
        save()
    }

    func setCaption(_ id: UUID, to caption: String) {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for p in projects.indices {
            for s in projects[p].scenes.indices {
                if let i = projects[p].scenes[s].shots.firstIndex(where: { $0.id == id }) {
                    projects[p].scenes[s].shots[i].caption = trimmed
                }
            }
        }
        save()
    }

    /// Frame lines can change after the fact; the still keeps the whole 16:9 frame.
    func setShotAspect(_ id: UUID, to aspect: AspectRatio) {
        for p in projects.indices {
            for s in projects[p].scenes.indices {
                if let i = projects[p].scenes[s].shots.firstIndex(where: { $0.id == id }) {
                    projects[p].scenes[s].shots[i].aspect = aspect
                }
            }
        }
        save()
    }

    /// Clears several shots at once (the Shot List's "delete all"), stills included.
    func deleteShots(_ ids: Set<UUID>) {
        for p in projects.indices {
            for s in projects[p].scenes.indices {
                for shot in projects[p].scenes[s].shots where ids.contains(shot.id) {
                    if let file = shot.photoFile {
                        try? FileManager.default.removeItem(at: Self.shotsFolder.appendingPathComponent(file))
                    }
                }
                projects[p].scenes[s].shots.removeAll { ids.contains($0.id) }
            }
        }
        save()
    }

    /// Deletes one project with its scenes, shots and stills. The last one can't vanish:
    /// deleting it leaves a fresh empty project, like delete all.
    func deleteProject(_ id: UUID) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        if projects.count == 1 {
            deleteAllProjects()
            return
        }
        for scene in project.scenes {
            for shot in scene.shots {
                if let file = shot.photoFile {
                    try? FileManager.default.removeItem(at: Self.shotsFolder.appendingPathComponent(file))
                }
            }
        }
        projects.removeAll { $0.id == id }
        if currentProjectID == id, let first = projects.first {
            currentProjectID = first.id
            currentSceneID = first.scenes.first?.id ?? currentSceneID
        }
        save()
    }

    /// Deletes one scene with its shots and stills. A project's last scene stays.
    func deleteScene(_ id: UUID) {
        guard let p = projects.firstIndex(where: { $0.scenes.contains { $0.id == id } }),
              projects[p].scenes.count > 1,
              let s = projects[p].scenes.firstIndex(where: { $0.id == id }) else { return }
        for shot in projects[p].scenes[s].shots {
            if let file = shot.photoFile {
                try? FileManager.default.removeItem(at: Self.shotsFolder.appendingPathComponent(file))
            }
        }
        projects[p].scenes.remove(at: s)
        if currentSceneID == id, projects[p].id == currentProjectID {
            currentSceneID = projects[p].scenes[max(0, s - 1)].id
        }
        save()
    }

    /// Wipes every project, scene, shot and still, and starts again with an empty project,
    /// just like a first launch. Kit, lens and aspect stay as they are.
    func deleteAllProjects() {
        try? FileManager.default.removeItem(at: Self.shotsFolder)
        let scene = ScoutScene(name: "Scene 1", note: Format.shortDate(Date()))
        let project = Project(name: "First Recce", kind: "", scenes: [scene])
        projects = [project]
        currentProjectID = project.id
        currentSceneID = scene.id
        save()
    }

    func deleteShot(_ id: UUID) {
        for p in projects.indices {
            for s in projects[p].scenes.indices {
                if let i = projects[p].scenes[s].shots.firstIndex(where: { $0.id == id }) {
                    if let file = projects[p].scenes[s].shots[i].photoFile {
                        try? FileManager.default.removeItem(at: Self.shotsFolder.appendingPathComponent(file))
                    }
                    projects[p].scenes[s].shots.remove(at: i)
                }
            }
        }
        save()
    }

    nonisolated static func photoURL(for shot: Shot) -> URL? {
        shot.photoFile.map { shotsFolder.appendingPathComponent($0) }
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var projects: [Project]
        var currentProjectID: UUID
        var currentSceneID: UUID
        var kit: Kit
        var lensMM: Double
        var aspect: AspectRatio
        var customAspects: [AspectRatio]
        var overlays: Overlays
        var locationChoice: LocationChoice?
    }

    func save() {
        let snap = Snapshot(
            projects: projects, currentProjectID: currentProjectID, currentSceneID: currentSceneID,
            kit: kit, lensMM: lensMM, aspect: aspect, customAspects: customAspects,
            overlays: overlays, locationChoice: locationChoice
        )
        do {
            let data = try JSONEncoder.scout.encode(snap)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            toast = "Couldn't save"
        }
    }

    nonisolated static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    nonisolated static var defaultURL: URL { documents.appendingPathComponent("outandscout.json") }
    nonisolated static var shotsFolder: URL { documents.appendingPathComponent("shots", isDirectory: true) }

    // MARK: Helpers

    private func updateProject(_ id: UUID, _ change: (inout Project) -> Void) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        change(&projects[i])
    }

    private func updateScene(_ id: UUID, _ change: (inout ScoutScene) -> Void) {
        for p in projects.indices {
            if let s = projects[p].scenes.firstIndex(where: { $0.id == id }) {
                change(&projects[p].scenes[s])
                return
            }
        }
    }
}

extension JSONEncoder {
    static var scout: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var scout: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
