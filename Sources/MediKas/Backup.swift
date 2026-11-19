import Foundation
import AppKit
import UniformTypeIdentifiers

/// Volledige back-ups (zip van gegevens + logo + factuurarchief) naar een tweede locatie,
/// bv. een externe schijf, NAS of een andere cloudmap. Los van de gegevensmap, zodat een
/// kapotte schijf of een per ongeluk gewiste cloudmap niet alles meeneemt.
///
/// Automatisch: één keer per dag (bij openen of activeren van de app), als de locatie bereikbaar is.
/// Bewaard: de laatste 30 back-ups plus de laatste van elke maand (voor altijd).
extension Store {
    private static let destKey = "backupFolderPath"
    private static let lastKey = "lastBackupDate"
    private static let problemKey = "lastBackupProblem"

    // MARK: Instellingen (per Mac)

    var backupDestination: URL? {
        get { UserDefaults.standard.string(forKey: Store.destKey).map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set {
            objectWillChange.send()
            guard !Store.isTestMode else { return }
            if let newValue { UserDefaults.standard.set(newValue.path, forKey: Store.destKey) }
            else { UserDefaults.standard.removeObject(forKey: Store.destKey) }
        }
    }

    var lastBackupDate: Date? { UserDefaults.standard.object(forKey: Store.lastKey) as? Date }
    var lastBackupProblem: String? { UserDefaults.standard.string(forKey: Store.problemKey) }

    var backupDestinationReachable: Bool { backupDestination.map(Store.isDirectory) ?? false }

    var isCloudFolder: Bool { !isDefaultFolder && folderKind.name != "Eigen map" }

    /// Waarschuwing voor het overzicht, of nil als alles in orde is.
    var safetyWarning: String? {
        if backupDestination == nil && !isCloudFolder {
            return "Je gegevens staan alleen op deze Mac. Kies een cloudmap (iCloud/Google Drive) of stel een back-uplocatie in, zodat je facturen veilig zijn als de Mac stukgaat."
        }
        if backupDestination != nil, let last = lastBackupDate, Date().timeIntervalSince(last) > 14 * 86400 {
            let days = Int(Date().timeIntervalSince(last) / 86400)
            return "De laatste back-up is \(days) dagen geleden gemaakt. Is de back-upschijf aangesloten?"
        }
        if backupDestination != nil && lastBackupDate == nil && !backupDestinationReachable {
            return "De back-uplocatie is niet bereikbaar, dus er is nog geen back-up gemaakt."
        }
        return nil
    }

    func chooseBackupDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Gebruik voor back-ups"
        panel.message = "Kies een tweede plek voor back-ups, bijvoorbeeld een externe schijf, NAS of een andere cloudmap dan je gegevensmap."
        guard panel.runModal() == .OK, let url = panel.url?.standardizedFileURL else { return }
        let data = folder.standardizedFileURL.path
        if url.path == data || url.path.hasPrefix(data + "/") {
            alert = "Kies een plek buiten de gegevensmap. Een back-up in dezelfde map beschermt je niet als die map verloren gaat."
            return
        }
        backupDestination = url
        backupNow()
    }

    // MARK: Back-up maken

    /// Eén keer per dag automatisch, als er een bereikbare back-uplocatie is.
    func runAutomaticBackup() {
        guard let dest = backupDestination, Store.isDirectory(dest), unavailableReason == nil, !isBackingUp, !isLoadingData else { return }
        let today = "MediKas-backup-\(Fmt.file.string(from: Date()))"
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: dest.path)) ?? []
        guard !existing.contains(where: { $0.hasPrefix(today) }) else { return }
        backup(to: dest.appendingPathComponent(Store.zipName()), prune: dest, announce: false)
    }

    /// Nu een back-up naar de ingestelde locatie.
    func backupNow() {
        guard let dest = backupDestination else { return }
        guard Store.isDirectory(dest) else {
            alert = "De back-uplocatie is niet bereikbaar:\n\(dest.path)\n\nIs de schijf aangesloten?"
            return
        }
        backup(to: dest.appendingPathComponent(Store.zipName()), prune: dest, announce: true)
    }

    /// Eenmalige back-up naar een zelfgekozen plek (bv. een USB-stick).
    func saveBackupAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Store.zipName()
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backup(to: url, prune: nil, announce: true)
    }

    private static func zipName() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmm"
        return "MediKas-backup-\(f.string(from: Date())).zip"
    }

    private func backup(to target: URL, prune: URL?, announce: Bool) {
        guard unavailableReason == nil, !isBackingUp else { return }
        saveNow()
        let source = folder
        let offline = Store.cloudPlaceholders(in: source)
        isBackingUp = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try Store.zip(source, to: target) }
            if case .success = result, let prune { Store.pruneZips(in: prune) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isBackingUp = false
                    self.objectWillChange.send()
                    switch result {
                    case .success:
                        if !Store.isTestMode { UserDefaults.standard.set(Date(), forKey: Store.lastKey) }
                        let note = offline > 0 ? "Let op: \(offline) bestand(en) stonden alleen in de cloud en zitten niet in deze back-up. Zet de map in de Finder op ‘Bewaar gedownload’." : nil
                        if let note { UserDefaults.standard.set(note, forKey: Store.problemKey) }
                        else { UserDefaults.standard.removeObject(forKey: Store.problemKey) }
                        if let note { self.alert = "Back-up gemaakt, maar onvolledig.\n\n" + note }
                        else if announce { self.show("Back-up gemaakt: \(target.lastPathComponent)") }
                    case .failure(let error):
                        UserDefaults.standard.set("Back-up mislukt: \(error.localizedDescription)", forKey: Store.problemKey)
                        self.alert = "Back-up mislukt: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    /// Zipt de gegevensmap (zonder de interne Backups-map; die zit al in eerdere zips).
    nonisolated static func zip(_ folder: URL, to target: URL) throws {
        let partial = target.deletingLastPathComponent().appendingPathComponent(".bezig-\(UUID().uuidString).zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = folder
        p.arguments = ["-r", "-q", "-X", partial.path, ".", "-x", "Backups/*", "*.icloud", "*.DS_Store", "data-onleesbaar-*"]
        let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: partial)
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "MediKas", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "zip gaf foutcode \(p.terminationStatus). \(msg)"])
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: partial, to: target)
    }

    /// Houd de laatste 30 automatische back-ups plus de laatste van elke maand.
    nonisolated static func pruneZips(in dest: URL) {
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: dest.path)) ?? [])
            .filter { $0.range(of: #"^MediKas-backup-\d{4}-\d{2}-\d{2}-\d{4}\.zip$"#, options: .regularExpression) != nil }
            .sorted(by: >)
        var keep = Set(names.prefix(30))
        var months = Set<String>()
        for n in names where months.insert(String(n.dropFirst("MediKas-backup-".count).prefix(7))).inserted { keep.insert(n) }
        for n in names where !keep.contains(n) { try? fm.removeItem(at: dest.appendingPathComponent(n)) }
    }

    /// Bestanden die door iCloud "uit de Mac verwijderd" zijn (alleen nog in de cloud). Start het downloaden.
    static func cloudPlaceholders(in folder: URL) -> Int {
        let fm = FileManager.default
        var count = 0
        let e = fm.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = e?.nextObject() as? URL {
            let name = url.lastPathComponent
            if url.pathComponents.contains("Backups") { continue }
            if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                count += 1
                let real = url.deletingLastPathComponent().appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
                try? fm.startDownloadingUbiquitousItem(at: real)
            }
        }
        return count
    }

    // MARK: Terugzetten

    /// Zet een back-up terug: een zip (volledig) of een losse data.json.
    func importBackup() {
        guard unavailableReason == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .json]
        panel.directoryURL = backupDestination ?? backupFolder
        panel.message = "Kies een MediKas-back-up (.zip of .json). De huidige gegevens worden vervangen; er wordt eerst een kopie gemaakt."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let fm = FileManager.default
        var dataFile = url
        var unpacked: URL?
        if url.pathExtension.lowercased() == "zip" {
            let tmp = fm.temporaryDirectory.appendingPathComponent("MediKas-herstel-\(UUID().uuidString)", isDirectory: true)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", url.path, tmp.path]
            do { try p.run(); p.waitUntilExit() } catch {}
            let candidate = [tmp.appendingPathComponent("data.json")] +
                (((try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []).map { $0.appendingPathComponent("data.json") })
            guard p.terminationStatus == 0, let found = candidate.first(where: { fm.fileExists(atPath: $0.path) }) else {
                alert = "In deze zip staat geen MediKas-back-up."
                return
            }
            dataFile = found
            unpacked = found.deletingLastPathComponent()
        }

        guard let restored = try? Store.decoder.decode(AppData.self, from: Data(contentsOf: dataFile)) else {
            alert = "Dit bestand is geen geldige MediKas-back-up."
            return
        }
        let a = NSAlert()
        a.messageText = "Back-up terugzetten?"
        a.informativeText = "De back-up bevat \(restored.invoices.count) facturen en \(restored.clients.count) praktijken. Je huidige gegevens (\(data.invoices.count) facturen) worden vervangen. Er wordt eerst een kopie gemaakt in Backups."
        a.addButton(withTitle: "Terugzetten")
        a.addButton(withTitle: "Annuleren")
        guard a.runModal() == .alertFirstButtonReturn else { return }

        saveNow()
        try? fm.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        try? fm.copyItem(at: dataURL, to: backupFolder.appendingPathComponent("data-voor-herstel-\(Int(Date().timeIntervalSince1970)).json"))
        undoable("Zet back-up terug") { data = restored }
        saveNow()
        if let unpacked {
            let logoFile = unpacked.appendingPathComponent("logo.png")
            if fm.fileExists(atPath: logoFile.path) {
                try? fm.removeItem(at: logoURL)
                try? fm.copyItem(at: logoFile, to: logoURL)
                logo = NSImage(contentsOf: logoURL)
            }
            // Archief-PDF's aanvullen (bestaande worden niet overschreven)
            Store.mergeCopy(from: unpacked.appendingPathComponent("Facturen", isDirectory: true), to: archiveFolder)
            Store.mergeCopy(from: unpacked.appendingPathComponent(Store.documentsFolderName, isDirectory: true), to: documentsRoot)
            try? fm.removeItem(at: unpacked)
        }
        show("Back-up teruggezet: \(restored.invoices.count) facturen, \(restored.clients.count) praktijken.")
    }
}
