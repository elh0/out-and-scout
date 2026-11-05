#if DEBUG
import CloudKit
import SwiftUI

/// Step 0 of the sync brief: prove CKSyncEngine, the web page and the public share loop.
/// Debug builds only, opened from a hidden row under Projects. Not part of the app.
@MainActor @Observable
final class CloudKitSpike: CKSyncEngineDelegate {
    static let container = CKContainer(identifier: "iCloud.com.outandscout.app")
    static let zoneID = CKRecordZone.ID(zoneName: "Scouts")
    static let testID = CKRecord.ID(recordName: "spike-test", zoneID: zoneID)
    private static let stateKey = "spikeSyncState"

    var log: [String] = []
    var title = ""
    var note = ""
    var modifiedAt: Date?
    var publicID = UserDefaults.standard.string(forKey: "spikePublicID") ?? ""

    private var engine: CKSyncEngine?
    private var lastRecord: CKRecord?

    func start() {
        guard engine == nil else { return }
        var saved: CKSyncEngine.State.Serialization?
        if let data = UserDefaults.standard.data(forKey: Self.stateKey) {
            saved = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }
        let config = CKSyncEngine.Configuration(
            database: Self.container.privateCloudDatabase, stateSerialization: saved, delegate: self)
        engine = CKSyncEngine(config)
        say("engine up")
        Task {
            do {
                let status = try await Self.container.accountStatus()
                say("account: \(status == .available ? "available" : "status \(status.rawValue)")")
            } catch { say("account error: \(error)") }
        }
    }

    /// b. Write one record to the private "Scouts" zone through the sync engine.
    func writeTest() async {
        guard let engine else { return }
        title = "Spike test"
        note = "Written on the phone \(Date().formatted(date: .omitted, time: .standard))"
        modifiedAt = .now
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(Self.testID)])
        do {
            try await engine.sendChanges()
            say("sent")
        } catch { say("send error: \(error)") }
    }

    /// b/c. Read it back: pull changes through the engine, then a direct fetch to be sure.
    func readBack() async {
        do {
            try await engine?.fetchChanges()
            say("fetched changes")
        } catch { say("fetch error: \(error)") }
        do {
            let record = try await Self.container.privateCloudDatabase.record(for: Self.testID)
            apply(record)
            say("direct read: \(title) / \(note)")
        } catch { say("direct read error: \(error)") }
    }

    /// d. One record in the public database, readable with no sign-in.
    func writePublic() async {
        let id = String((0..<10).map { _ in "abcdefghjkmnpqrstuvwxyz23456789".randomElement()! })
        let record = CKRecord(recordType: "SpikeShare", recordID: CKRecord.ID(recordName: id))
        record["title"] = "Public spike"
        record["note"] = "Written on the phone \(Date().formatted(date: .abbreviated, time: .shortened))"
        record["expiresAt"] = Date.now.addingTimeInterval(90 * 86_400)
        do {
            _ = try await Self.container.publicCloudDatabase.save(record)
            publicID = id
            UserDefaults.standard.set(id, forKey: "spikePublicID")
            UIPasteboard.general.string = id
            say("public saved: \(id) (copied)")
        } catch { say("public error: \(error)") }
    }

    private func apply(_ record: CKRecord) {
        lastRecord = record
        title = record["title"] as? String ?? ""
        note = record["note"] as? String ?? ""
        modifiedAt = record["modifiedAt"] as? Date
    }

    private func say(_ line: String) {
        log.insert("\(Date().formatted(date: .omitted, time: .standard))  \(line)", at: 0)
        print("[spike] \(line)")
    }

    // MARK: CKSyncEngineDelegate

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await MainActor.run { self.handle(event) }
    }

    private func handle(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                UserDefaults.standard.set(data, forKey: Self.stateKey)
            }
        case .accountChange(let change):
            say("account change: \(change.changeType)")
        case .fetchedRecordZoneChanges(let changes):
            for mod in changes.modifications where mod.record.recordID == Self.testID {
                apply(mod.record)
                say("engine got: \(title) / \(note)")
            }
        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords { apply(record); say("saved \(record.recordID.recordName)") }
            for failed in sent.failedRecordSaves {
                say("save failed: \(failed.error.code.rawValue) \(failed.error.localizedDescription)")
                if failed.error.code == .serverRecordChanged, let server = failed.error.serverRecord {
                    apply(server)
                    say("took server copy; write again to overwrite")
                }
            }
        case .sentDatabaseChanges(let sent):
            for zone in sent.savedZones { say("zone saved: \(zone.zoneID.zoneName)") }
            for failed in sent.failedZoneSaves { say("zone failed: \(failed.error)") }
        default:
            break
        }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        let snapshot = await MainActor.run { (self.lastRecord, self.title, self.note) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            let record = (snapshot.0?.recordID == id ? snapshot.0 : nil) ?? CKRecord(recordType: "SpikeNote", recordID: id)
            record["title"] = snapshot.1
            record["note"] = snapshot.2
            record["modifiedAt"] = Date.now
            return record
        }
    }
}

struct CloudKitSpikeView: View {
    @State private var spike = CloudKitSpike()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CLOUDKIT SPIKE")
                Spacer()
                Button("DONE") { dismiss() }
            }
            Text("private · Scouts · spike-test").foregroundStyle(.secondary)
            Text("title: \(spike.title)")
            Text("note: \(spike.note)")
            Text("modified: \(spike.modifiedAt?.formatted(date: .omitted, time: .standard) ?? "-")")
            Button("WRITE TEST RECORD") { Task { await spike.writeTest() } }
            Button("READ BACK") { Task { await spike.readBack() } }
            Divider()
            Text("public: \(spike.publicID.isEmpty ? "-" : spike.publicID)").textSelection(.enabled)
            Button("WRITE PUBLIC RECORD") { Task { await spike.writePublic() } }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(spike.log.enumerated()), id: \.offset) { Text($0.element).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.osRow)
        .buttonStyle(.plain)
        .padding(24)
        .onAppear { spike.start() }
    }
}
#endif
