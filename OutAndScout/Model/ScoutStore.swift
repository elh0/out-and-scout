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
    /// The scene the Name-this-scene card is open for.
    var namingSceneID: UUID?
    var pending: PendingShot?
    var toast: String?

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
            // No setup before first use: a project and a scene are ready to pin into.
            let scene = ScoutScene(name: "scene 1", note: Format.shortDate(Date()))
            let project = Project(name: "first recce", kind: "", scenes: [scene])
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
    }

    // MARK: Lookups

    var currentProject: Project {
        projects.first { $0.id == currentProjectID } ?? projects[0]
    }

    var currentScene: ScoutScene {
        currentProject.scenes.first { $0.id == currentSceneID } ?? currentProject.scenes[0]
    }

    /// "5A": the next setup number in the current scene.
    var nextShotNumber: String {
        "\(currentScene.shots.count + 1)A"
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
            askingLocation = true
        } else {
            addScene()
        }
    }

    @discardableResult
    func addScene(named name: String? = nil, location: ShotLocation? = nil) -> UUID {
        let index = currentProject.scenes.count + 1
        let scene = ScoutScene(
            name: name ?? location?.label ?? "scene \(index)",
            note: Format.shortDate(Date()),
            location: location
        )
        updateProject(currentProjectID) { $0.scenes.append(scene) }
        currentSceneID = scene.id
        namingSceneID = scene.id
        save()
        return scene.id
    }

    func renameScene(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        updateScene(id) { $0.name = trimmed }
        save()
    }

    func addProject(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        let scene = ScoutScene(name: "scene 1", note: Format.shortDate(Date()))
        let project = Project(name: trimmed, kind: "", scenes: [scene])
        projects.append(project)
        currentProjectID = project.id
        currentSceneID = scene.id
        save()
    }

    // MARK: Shots

    func commitPending(caption: String) {
        guard let p = pending else { return }
        var photoFile: String?
        if let data = p.photo {
            let name = "\(p.id.uuidString).heic"
            do {
                try FileManager.default.createDirectory(at: Self.shotsFolder, withIntermediateDirectories: true)
                try data.write(to: Self.shotsFolder.appendingPathComponent(name), options: .atomic)
                photoFile = name
            } catch {
                toast = "couldn't save the still"
            }
        }
        let shot = Shot(
            id: p.id,
            number: p.number,
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            lensMM: p.lensMM,
            aspect: aspect,
            cameraName: kit.camera.name,
            lensSeries: kit.lenses.name,
            plannedTime: p.plannedTime,
            capturedAt: Date(),
            sunAzimuth: p.sun.azimuth,
            sunElevation: p.sun.elevation,
            light: p.light,
            bearing: p.bearing,
            location: p.location,
            photoFile: photoFile
        )
        updateScene(currentSceneID) { $0.shots.append(shot) }
        pending = nil
        toast = "saved \(shot.number)"
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

    static func photoURL(for shot: Shot) -> URL? {
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
            toast = "couldn't save"
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
