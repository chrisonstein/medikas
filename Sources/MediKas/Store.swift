import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overzicht = "Overzicht"
    case facturen = "Facturen"
    case betalingen = "Betalingen"
    case praktijken = "Praktijken"
    case statistieken = "Statistieken"
    var id: Self { self }

    var icon: String {
        switch self {
        case .overzicht: "house"
        case .facturen: "doc.text"
        case .betalingen: "eurosign.circle"
        case .praktijken: "cross.case"
        case .statistieken: "chart.bar.xaxis"
        }
    }
}

/// Houdt alle gegevens bij. Alles staat in één instelbare gegevensmap
/// (standaard ~/Library/Application Support/MediKas, of bv. iCloud Drive / Google Drive):
///
///     data.json            alle gegevens
///     logo.png             logo voor de factuur
///     Backups/             dagelijkse kopieën van data.json
///     Facturen/<jaar>/     PDF van elke verstuurde factuur (bewaarplicht 7 jaar)
@MainActor
final class Store: ObservableObject {
    @Published var data: AppData { didSet { if !isLoading { scheduleSave() } } }
    @Published var sidebar: SidebarItem? = .overzicht
    @Published var editingInvoice: Invoice?
    @Published var paymentInvoice: Invoice?
    @Published var logo: NSImage?
    /// Fouten en echte waarschuwingen: getoond als standaard macOS-melding (sheet op het actieve venster).
    /// Eerste regel = titel, de rest = toelichting.
    @Published var alert: String? { didSet { if let alert, alert != oldValue { presentAlert(alert) } } }
    @Published var selectedClientID: UUID?
    @Published var clientToDelete: Client?
    /// Bevestigingen (niet-modaal, verdwijnt vanzelf).
    @Published var notice: String?
    /// Undo-manager van het venster (⌘Z), gezet door ContentView.
    weak var undoManager: UndoManager?

    /// De gegevensmap die nu gebruikt wordt.
    @Published private(set) var folder: URL
    /// Gezet als de map niet bereikbaar is (bv. Google Drive draait niet). Er wordt dan niets opgeslagen.
    @Published private(set) var unavailableReason: String?
    /// Bezig met een zip-back-up (zie Backup.swift).
    @Published var isBackingUp = false

    var dataURL: URL { folder.appendingPathComponent("data.json") }
    var logoURL: URL { folder.appendingPathComponent("logo.png") }
    var backupFolder: URL { folder.appendingPathComponent("Backups", isDirectory: true) }
    var archiveFolder: URL { folder.appendingPathComponent("Facturen", isDirectory: true) }

    static let defaultFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MediKas", isDirectory: true)
    private static let folderKey = "dataFolderPath"

    private var saveWork: DispatchWorkItem?
    private var isLoading = false
    private var lastModDate: Date?
    /// True zolang de gegevens bij het opstarten nog worden ingelezen (bv. uit iCloud).
    /// Pagina's tonen dan een laadtoestand in plaats van een lege toestand, en er wordt niets opgeslagen.
    @Published private(set) var isLoadingData = false

    /// De actieve store (voor de testmodus die het echte venster vastlegt).
    static weak var current: Store?

    /// `loadAsync`: lees de gegevens op de achtergrond in (de app blijft vlot, ook als iCloud nog moet downloaden).
    init(loadAsync: Bool = true) {
        folder = Store.configuredFolder()
        data = AppData()
        if loadAsync { loadInBackground() } else { load(); seedDemoIfRequested() }

        Store.current = self
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        // Gewijzigd op een andere Mac (via iCloud/Google Drive)? Dan opnieuw inlezen.
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfChangedExternally() }
        }
    }

    // MARK: Gegevensmap

    private static func configuredFolder() -> URL {
        if let env = ProcessInfo.processInfo.environment["MEDIKAS_DATA_DIR"] {   // om te testen
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        if let path = UserDefaults.standard.string(forKey: folderKey) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultFolder
    }

    var isDefaultFolder: Bool { folder.standardizedFileURL.path == Store.defaultFolder.standardizedFileURL.path }

    var folderKind: (name: String, icon: String) {
        let p = folder.path
        if p.contains("/Mobile Documents/") { return ("iCloud Drive", "icloud") }
        if p.contains("/CloudStorage/GoogleDrive") { return ("Google Drive", "externaldrive.badge.icloud") }
        if p.contains("/CloudStorage/OneDrive") { return ("OneDrive", "externaldrive.badge.icloud") }
        if p.contains("/CloudStorage/Dropbox") || p.contains("/Dropbox/") { return ("Dropbox", "externaldrive.badge.icloud") }
        return isDefaultFolder ? ("Alleen op deze Mac", "desktopcomputer") : ("Eigen map", "folder")
    }

    static var iCloudDriveRoot: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// "Mijn Drive" van elk Google Drive-account dat in de Finder gekoppeld is.
    static var googleDriveRoots: [URL] {
        let fm = FileManager.default
        let cloud = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let accounts = ((try? fm.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("GoogleDrive-") }
        return accounts.compactMap { acc in
            ["Mijn Drive", "My Drive"].map { acc.appendingPathComponent($0, isDirectory: true) }
                .first { fm.fileExists(atPath: $0.path) }
        }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    private func seedDemoIfRequested() {
        if CommandLine.arguments.contains("--seed-demo") && data.invoices.isEmpty && unavailableReason == nil {
            data = Demo.sampleData()
        }
    }

    /// Controleert de map; nil als die niet bereikbaar is (dan staat unavailableReason gezet).
    private func prepareLoad() -> Bool {
        saveWork?.cancel(); saveWork = nil
        if isDefaultFolder { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        guard Store.isDirectory(folder) else {
            isLoading = true
            unavailableReason = "De gegevensmap is niet bereikbaar:\n\(folder.path)\n\nStaat iCloud Drive of Google Drive aan en is de map gesynchroniseerd?"
            data = AppData(); logo = nil
            isLoading = false
            return false
        }
        return true
    }

    /// Leest data.json; nil als het bestand (nog) niet bestaat. Mag op een achtergrondthread.
    nonisolated private static func readData(dataURL: URL, folder: URL) throws -> Data? {
        let fm = FileManager.default
        // Testvlag: trage opslag (zoals iCloud die nog downloadt) nabootsen.
        if let delay = ProcessInfo.processInfo.environment["MEDIKAS_TEST_SLOW_LOAD"].flatMap(Double.init) {
            Thread.sleep(forTimeInterval: delay)
        }
        let placeholder = folder.appendingPathComponent(".data.json.icloud")
        guard fm.fileExists(atPath: dataURL.path) || fm.fileExists(atPath: placeholder.path) else { return nil }
        try? fm.startDownloadingUbiquitousItem(at: dataURL)
        return try readCoordinated(dataURL)
    }

    /// Verwerkt de ingelezen gegevens (altijd op de hoofdthread).
    private func finishLoad(_ result: Result<Data?, Error>) {
        isLoading = true
        defer { isLoading = false }
        let fm = FileManager.default
        var loaded = AppData()
        switch result {
        case .failure(let error):
            unavailableReason = "data.json in \(folder.path) kon niet geopend worden (nog niet gedownload?).\n\n\(error.localizedDescription)"
            data = AppData(); logo = nil
            return
        case .success(let raw?):
            do {
                loaded = try Store.decoder.decode(AppData.self, from: raw)
            } catch {
                // Nooit stilletjes overschrijven: zet het bestand opzij.
                let aside = folder.appendingPathComponent("data-onleesbaar-\(Int(Date().timeIntervalSince1970)).json")
                try? fm.copyItem(at: dataURL, to: aside)
                alert = "Het gegevensbestand kon niet gelezen worden. Een kopie staat in \(aside.lastPathComponent). Zet eventueel een back-up terug via Instellingen → Opslag."
            }
        case .success(nil):
            break
        }
        unavailableReason = nil
        try? fm.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        data = loaded
        logo = NSImage(contentsOf: logoURL)
        lastModDate = Store.modDate(dataURL)
        makeDailyBackup()
        DispatchQueue.main.async { [weak self] in self?.runAutomaticBackup() }
    }

    /// Leest data.json (opnieuw) in uit de huidige map, direct.
    func load() {
        guard prepareLoad() else { return }
        finishLoad(Result { try Store.readData(dataURL: dataURL, folder: folder) })
    }

    /// Eerste keer inlezen bij het opstarten: op de achtergrond, met laadtoestand in de schermen.
    private func loadInBackground() {
        guard prepareLoad() else { return }
        isLoadingData = true
        let dataURL = dataURL, folder = folder
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try Store.readData(dataURL: dataURL, folder: folder) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.finishLoad(result)
                    self.seedDemoIfRequested()
                    withAnimation(.easeOut(duration: 0.25)) { self.isLoadingData = false }
                }
            }
        }
    }

    func reloadIfChangedExternally() {
        guard !isLoadingData else { return }
        runAutomaticBackup()
        if unavailableReason != nil { load(); return }
        guard saveWork == nil, let current = Store.modDate(dataURL), current != lastModDate else { return }
        load()
    }

    /// Kies een map via een venster. Lege of nieuwe map → direct gebruikt; een map met andere bestanden → submap "MediKas".
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Gebruik deze map"
        panel.message = "Kies waar MediKas de gegevens en het factuurarchief bewaart, bijvoorbeeld in iCloud Drive of Google Drive."
        panel.directoryURL = Store.iCloudDriveRoot ?? folder
        guard panel.runModal() == .OK, var url = panel.url else { return }
        let fm = FileManager.default
        let contents = ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") || $0 == ".data.json.icloud" }
        let isAppFolder = contents.contains("data.json") || contents.contains(".data.json.icloud")
        if !contents.isEmpty && !isAppFolder {
            url = url.appendingPathComponent("MediKas", isDirectory: true)
        }
        changeFolder(to: url)
    }

    func useICloudDrive() {
        guard let root = Store.iCloudDriveRoot else {
            alert = "iCloud Drive staat niet aan op deze Mac. Zet het aan via Systeeminstellingen → [je naam] → iCloud → iCloud Drive."
            return
        }
        changeFolder(to: root.appendingPathComponent("MediKas", isDirectory: true))
    }

    func useDefaultFolder() { changeFolder(to: Store.defaultFolder) }

    /// Verhuist naar een andere map. Bestaande gegevens worden gekopieerd; de oude map blijft staan.
    func changeFolder(to target: URL) {
        let fm = FileManager.default
        let target = target.standardizedFileURL
        let old = folder
        guard target.path != folder.standardizedFileURL.path else { return }
        if target.path.hasPrefix(folder.standardizedFileURL.path + "/") {
            alert = "Kies een map buiten de huidige gegevensmap."
            return
        }
        let canCopy = unavailableReason == nil
        if canCopy { saveNow() }

        do { try fm.createDirectory(at: target, withIntermediateDirectories: true) }
        catch { alert = "Kan de map niet aanmaken: \(error.localizedDescription)"; return }

        let targetData = target.appendingPathComponent("data.json")
        let hasData = fm.fileExists(atPath: targetData.path) || fm.fileExists(atPath: target.appendingPathComponent(".data.json.icloud").path)
        var replace = true
        if hasData {
            let a = NSAlert()
            a.messageText = "Deze map bevat al MediKas-gegevens"
            a.informativeText = "Wil je de gegevens uit die map gebruiken, of ze vervangen door de gegevens van deze Mac? Bij vervangen wordt eerst een kopie in Backups gezet."
            a.addButton(withTitle: "Gegevens uit die map gebruiken")
            a.addButton(withTitle: "Vervangen")
            a.addButton(withTitle: "Annuleren")
            switch a.runModal() {
            case .alertFirstButtonReturn: replace = false
            case .alertSecondButtonReturn:
                let backups = target.appendingPathComponent("Backups", isDirectory: true)
                try? fm.createDirectory(at: backups, withIntermediateDirectories: true)
                try? fm.copyItem(at: targetData, to: backups.appendingPathComponent("data-voor-vervangen-\(Int(Date().timeIntervalSince1970)).json"))
            default: return
            }
        }

        if canCopy && replace {
            do {
                if fm.fileExists(atPath: dataURL.path) {
                    let raw = try Data(contentsOf: dataURL)
                    try Store.writeCoordinated(raw, to: targetData)
                }
                let targetLogo = target.appendingPathComponent("logo.png")
                if fm.fileExists(atPath: logoURL.path) {
                    try? fm.removeItem(at: targetLogo)
                    try? fm.copyItem(at: logoURL, to: targetLogo)
                }
                Store.mergeCopy(from: backupFolder, to: target.appendingPathComponent("Backups", isDirectory: true))
                Store.mergeCopy(from: archiveFolder, to: target.appendingPathComponent("Facturen", isDirectory: true))
            } catch {
                alert = "Kopiëren naar de nieuwe map mislukt: \(error.localizedDescription)"
                return
            }
        }

        if target.path == Store.defaultFolder.standardizedFileURL.path {
            UserDefaults.standard.removeObject(forKey: Store.folderKey)
        } else {
            UserDefaults.standard.set(target.path, forKey: Store.folderKey)
        }
        folder = target
        load()
        if unavailableReason == nil {
            show("Gegevens verplaatst naar \(folderKind.name). De oude map is bewaard (\(old.lastPathComponent)).")
        }
    }

    /// Kopieert bestanden die in de doelmap nog ontbreken (overschrijft niets).
    static func mergeCopy(from source: URL, to target: URL) {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let url as URL in e {
            let rel = String(url.standardizedFileURL.path.dropFirst(source.standardizedFileURL.path.count + 1))
            let dest = target.appendingPathComponent(rel)
            if isDirectory(url) {
                try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            } else if !fm.fileExists(atPath: dest.path) {
                try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.copyItem(at: url, to: dest)
            }
        }
    }

    // MARK: Opslaan

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // Gecoördineerd lezen/schrijven: zo spelen iCloud Drive en Google Drive netjes mee.
    nonisolated static func readCoordinated(_ url: URL) throws -> Data {
        var coordError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            result = Result { try Data(contentsOf: u) }
        }
        if let coordError { throw coordError }
        return try result.get()
    }

    nonisolated static func writeCoordinated(_ data: Data, to url: URL) throws {
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { u in
            do { try data.write(to: u, options: .atomic) } catch { writeError = error }
        }
        if let e = (coordError as Error?) ?? writeError { throw e }
    }

    private static func modDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.saveNow() } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        saveWork?.cancel(); saveWork = nil
        // Nooit opslaan terwijl de gegevens nog worden ingelezen: dat zou de echte gegevens overschrijven.
        guard unavailableReason == nil, !isLoadingData else { return }
        do {
            try Store.writeCoordinated(Store.encoder.encode(data), to: dataURL)
            lastModDate = Store.modDate(dataURL)
        } catch {
            alert = "Opslaan mislukt: \(error.localizedDescription)"
        }
    }

    /// Eén back-up per dag. Bewaard: de laatste 90 dagen, plus de laatste van elke maand (voor altijd).
    private func makeDailyBackup() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dataURL.path) else { return }
        let target = backupFolder.appendingPathComponent("data-\(Fmt.file.string(from: Date())).json")
        if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: dataURL, to: target) }

        let names = ((try? fm.contentsOfDirectory(atPath: backupFolder.path)) ?? [])
            .filter { $0.range(of: #"^data-\d{4}-\d{2}-\d{2}\.json$"#, options: .regularExpression) != nil }
            .sorted(by: >)
        var keep = Set(names.prefix(90))
        var seenMonths = Set<String>()
        for n in names where seenMonths.insert(String(n.dropFirst(5).prefix(7))).inserted { keep.insert(n) }
        for n in names where !keep.contains(n) { try? fm.removeItem(at: backupFolder.appendingPathComponent(n)) }
    }

    // MARK: Factuurarchief (PDF's)

    /// Bewaart de PDF van een verstuurde factuur in Facturen/<jaar>/ in de gegevensmap.
    /// `keepPrevious`: bewaar de bestaande PDF eerst als eerdere versie (bij aanpassen van een verstuurde factuur).
    func archivePDF(_ id: UUID, keepPrevious: Bool = false) {
        guard data.settings.archivePDFs, unavailableReason == nil,
              let i = data.invoices.firstIndex(where: { $0.id == id }), data.invoices[i].isSent else { return }
        let inv = data.invoices[i]
        guard let pdf = InvoicePDF.data(for: inv, settings: data.settings, logo: logo) else { return }
        let rel = "Facturen/\(inv.date.year)/\(InvoicePDF.fileName(inv))"
        let url = folder.appendingPathComponent(rel)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if keepPrevious, let existing = archivedURL(inv) {
                let versions = folder.appendingPathComponent("Facturen/Eerdere versies", isDirectory: true)
                try? FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
                let stamp = DateFormatter.versionStamp.string(from: Date())
                let name = existing.deletingPathExtension().lastPathComponent + " (vervangen \(stamp)).pdf"
                try? FileManager.default.copyItem(at: existing, to: versions.appendingPathComponent(name))
            }
            try Store.writeCoordinated(pdf, to: url)
            if let old = inv.archivedFile, old != rel {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(old))
            }
            if inv.archivedFile != rel { data.invoices[i].archivedFile = rel }
        } catch {
            alert = "PDF archiveren mislukt: \(error.localizedDescription)"
        }
    }

    func archivedURL(_ invoice: Invoice) -> URL? {
        guard let rel = invoice.archivedFile else { return nil }
        let url = folder.appendingPathComponent(rel)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Maakt PDF's aan voor verstuurde facturen die nog niet (meer) in het archief staan.
    func archiveMissing() {
        let missing = data.invoices.filter { $0.isSent && archivedURL($0) == nil }
        for inv in missing { archivePDF(inv.id) }
        show(missing.isEmpty ? "Alle verstuurde facturen staan al in het archief." : "\(missing.count) factu\(missing.count == 1 ? "ur" : "ren") gearchiveerd.")
    }

    func openArchive() {
        try? FileManager.default.createDirectory(at: archiveFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(archiveFolder)
    }

    // MARK: Logo

    func chooseLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .pdf]
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: logoURL)
        logo = NSImage(data: png)
    }

    func removeLogo() {
        try? FileManager.default.removeItem(at: logoURL)
        logo = nil
    }

    // MARK: Ongedaan maken & meldingen

    /// Voert een wijziging uit die met ⌘Z ongedaan gemaakt kan worden.
    func undoable(_ name: String, _ change: () -> Void) {
        let before = data
        change()
        registerUndo(restoring: before, name: name)
    }

    private func registerUndo(restoring old: AppData, name: String) {
        guard let undoManager else { return }
        let current = data
        undoManager.registerUndo(withTarget: self) { store in
            store.data = old
            store.registerUndo(restoring: current, name: name)
        }
        undoManager.setActionName(name)
    }

    private func presentAlert(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            let parts = message.components(separatedBy: "\n").filter { !$0.isEmpty }
            let a = NSAlert()
            a.messageText = parts.first ?? message
            a.informativeText = parts.dropFirst().joined(separator: "\n")
            a.addButton(withTitle: "OK")
            if let window = NSApp.keyWindow, window.attachedSheet == nil {
                a.beginSheetModal(for: window) { _ in self?.alert = nil }
            } else {
                a.runModal()
                self?.alert = nil
            }
        }
    }

    private var noticeWork: DispatchWorkItem?

    func show(_ message: String) {
        notice = message
        AccessibilityNotification.Announcement(message).post()   // VoiceOver leest de bevestiging voor
        noticeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.notice = nil } }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    // MARK: Praktijken

    var activeClients: [Client] {
        data.clients.filter { !$0.archived }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func client(_ id: UUID?) -> Client? { data.clients.first { $0.id == id } }

    /// Nieuwe praktijk met de standaardtarieven uit de instellingen.
    @discardableResult
    func addClient() -> Client {
        var c = Client()
        c.hourlyRate = data.settings.defaultHourlyRate
        c.kmRate = data.settings.defaultKmRate
        undoable("Nieuwe praktijk") { data.clients.append(c) }
        return c
    }

    func invoiceCount(for client: Client) -> Int { data.invoices.filter { $0.clientID == client.id }.count }

    /// Wat er gebeurt als je een praktijk verwijdert.
    enum ClientRemoval {
        /// Geen facturen: gewoon verwijderen.
        case delete
        /// Alleen concepten: praktijk + concepten verwijderen.
        case deleteWithConcepts(Int)
        /// Er zijn verstuurde facturen: niet verwijderen (boekhouding), alleen archiveren.
        case archiveOnly(sent: Int)
    }

    func removal(for client: Client) -> ClientRemoval {
        let linked = data.invoices.filter { $0.clientID == client.id }
        let sent = linked.filter(\.isSent).count
        if sent > 0 { return .archiveOnly(sent: sent) }
        return linked.isEmpty ? .delete : .deleteWithConcepts(linked.count)
    }

    /// Praktijk die wacht op bevestiging van verwijderen (dialoog in ClientsView).
    func requestDelete(_ client: Client) { clientToDelete = client }

    func deleteClient(_ client: Client) {
        let name = client.displayName
        let kind = removal(for: client)
        if case .archiveOnly = kind {} else if selectedClientID == client.id { selectedClientID = nil }
        switch kind {
        case .delete:
            undoable("Verwijder praktijk") { data.clients.removeAll { $0.id == client.id } }
            show("\(name) verwijderd. Ongedaan maken met ⌘Z.")
        case .deleteWithConcepts(let n):
            undoable("Verwijder praktijk") {
                data.invoices.removeAll { $0.clientID == client.id && !$0.isSent }
                data.clients.removeAll { $0.id == client.id }
            }
            show("\(name) en \(n) concept\(n == 1 ? "" : "en") verwijderd. Ongedaan maken met ⌘Z.")
        case .archiveOnly:
            setArchived(client, true)
        }
    }

    func setArchived(_ client: Client, _ archived: Bool) {
        undoable(archived ? "Archiveer praktijk" : "Zet praktijk terug") {
            if let i = data.clients.firstIndex(where: { $0.id == client.id }) { data.clients[i].archived = archived }
        }
        show(archived ? "\(client.displayName) gearchiveerd. De facturen blijven bewaard." : "\(client.displayName) is weer actief.")
    }

    func hourlyRate(for client: Client?) -> Decimal {
        if let r = client?.hourlyRate, r > 0 { return r }
        return data.settings.defaultHourlyRate
    }

    func kmRate(for client: Client?) -> Decimal {
        if let r = client?.kmRate, r > 0 { return r }
        return data.settings.defaultKmRate
    }

    // MARK: Facturen

    var years: [Int] {
        var set = Set(data.invoices.map(\.date.year))
        set.formUnion(data.invoices.flatMap { $0.payments.map(\.date.year) })
        set.insert(Date().year)
        return set.sorted(by: >)
    }

    func nextInvoiceNumber(for date: Date, excluding: UUID? = nil) -> String {
        let prefix = "\(data.settings.invoicePrefix)\(date.year)-"
        let used = data.invoices
            .filter { $0.id != excluding && $0.number.hasPrefix(prefix) }
            .compactMap { Int($0.number.dropFirst(prefix.count)) }
        return prefix + String(format: "%03d", (used.max() ?? 0) + 1)
    }

    func isDuplicateNumber(_ number: String, id: UUID) -> Bool {
        data.invoices.contains { $0.id != id && $0.number == number }
    }

    func makeInvoice(for client: Client?) -> Invoice {
        var inv = Invoice()
        let today = Date().startOfDay
        inv.date = today
        inv.dueDate = today.adding(days: data.settings.paymentTermDays)
        inv.number = nextInvoiceNumber(for: today)
        if let client {
            inv.clientID = client.id
            inv.billTo = client
        }
        inv.kmRate = kmRate(for: client)
        var line = WorkLine()
        line.description = data.settings.defaultLineDescription
        line.hourlyRate = hourlyRate(for: client)
        line.commuteKm = client?.commuteKm ?? 0
        inv.lines = [line]
        return inv
    }

    func startNewInvoice(for client: Client? = nil) {
        editingInvoice = makeInvoice(for: client ?? activeClients.first)
    }

    func edit(_ invoice: Invoice) { editingInvoice = invoice }

    func isSaved(_ invoice: Invoice) -> Bool { data.invoices.contains { $0.id == invoice.id } }

    func save(_ invoice: Invoice) {
        undoable(isSaved(invoice) ? "Wijzig factuur" : "Nieuwe factuur") { saveWithoutUndo(invoice) }
    }

    private func saveWithoutUndo(_ invoice: Invoice) {
        var inv = invoice
        if let c = client(inv.clientID) { inv.billTo = c }
        var documentChanged = true
        var wasSent = false
        if let i = data.invoices.firstIndex(where: { $0.id == inv.id }) {
            let previous = data.invoices[i]
            inv.archivedFile = previous.archivedFile
            documentChanged = Store.fingerprint(previous) != Store.fingerprint(inv)
            wasSent = previous.isSent
            if wasSent && documentChanged { inv.editedAfterSending.append(Date()) }
            data.invoices[i] = inv
        } else {
            data.invoices.append(inv)
        }
        // Alleen een nieuwe PDF als de factuur zelf veranderde (niet bij alleen een betaling of opmerking)
        if inv.isSent && (documentChanged || archivedURL(inv) == nil || !wasSent) {
            archivePDF(inv.id, keepPrevious: wasSent && documentChanged)
        }
    }

    /// Wat er op de factuur staat (om te zien of de factuur zelf veranderd is).
    private static func fingerprint(_ i: Invoice) -> String {
        struct Doc: Encodable {
            let number: String; let date: Date; let dueDate: Date; let billTo: Client; let lines: [WorkLine]
            let kmRate: Decimal; let notes: String; let kind: InvoiceKind; let relatedNumber: String
        }
        let doc = Doc(number: i.number, date: i.date, dueDate: i.dueDate, billTo: i.billTo, lines: i.lines,
                      kmRate: i.kmRate, notes: i.notes, kind: i.kind, relatedNumber: i.relatedNumber)
        return (try? String(data: encoder.encode(doc), encoding: .utf8)) ?? UUID().uuidString
    }

    func invoice(_ id: UUID?) -> Invoice? { id.flatMap { id in data.invoices.first { $0.id == id } } }

    // MARK: Corrigeren (creditfactuur + nieuwe factuur)

    /// Maakt een creditfactuur die `original` volledig crediteert, en optioneel een nieuwe factuur
    /// (kopie, om aan te passen). Alles wordt aan elkaar gekoppeld. Geeft de factuur terug die geopend moet worden.
    @discardableResult
    func correct(_ original: Invoice, reissue: Bool) -> Invoice? {
        guard let oi = data.invoices.firstIndex(where: { $0.id == original.id }), !original.isCredit else { return nil }
        let today = Date().startOfDay
        var credit = Invoice()
        var replacement: Invoice?
        undoable(reissue ? "Corrigeer factuur" : "Crediteer factuur") {
            credit.kind = .credit
            credit.number = nextInvoiceNumber(for: today)
            credit.date = today
            credit.dueDate = today
            credit.clientID = original.clientID
            credit.billTo = client(original.clientID) ?? original.billTo
            credit.kmRate = original.kmRate
            credit.lines = original.sortedLines.map { l in
                var c = l; c.id = UUID(); c.hours = -l.hours; c.commuteKm = -l.commuteKm; c.visitKm = -l.visitKm; return c
            }
            credit.creditsInvoiceID = original.id
            credit.relatedNumber = original.number
            credit.relatedDate = original.date
            data.invoices.append(credit)
            data.invoices[oi].creditedByID = credit.id

            if reissue {
                var new = makeInvoice(for: client(original.clientID))
                new.number = nextInvoiceNumber(for: today)
                new.kmRate = original.kmRate
                new.lines = original.sortedLines.map { var l = $0; l.id = UUID(); return l }
                new.notes = original.notes
                new.replacesInvoiceID = original.id
                new.relatedNumber = original.number
                new.relatedDate = original.date
                data.invoices.append(new)
                data.invoices[oi].replacedByID = new.id
                replacement = new
            }
        }
        if let replacement {
            show("Creditfactuur \(credit.number) en nieuwe factuur \(replacement.number) aangemaakt als concept.")
        } else {
            show("Creditfactuur \(credit.number) aangemaakt als concept.")
        }
        return replacement ?? credit
    }

    /// Korte omschrijving van de koppeling, bv. "crediteert 2026-003".
    func linkSummary(_ inv: Invoice) -> String? {
        var parts: [String] = []
        if let c = invoice(inv.creditsInvoiceID) { parts.append("crediteert \(c.number)") }
        if let r = invoice(inv.replacesInvoiceID) { parts.append("vervangt \(r.number)") }
        if let c = invoice(inv.creditedByID) { parts.append("gecrediteerd met \(c.number)") }
        if let r = invoice(inv.replacedByID) { parts.append("vervangen door \(r.number)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func delete(_ invoice: Invoice) {
        // De gearchiveerde PDF blijft bewaard (bewaarplicht), maar gaat naar Facturen/Verwijderd.
        if let url = archivedURL(invoice) {
            let dest = archiveFolder.appendingPathComponent("Verwijderd", isDirectory: true)
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: url, to: dest.appendingPathComponent(url.lastPathComponent))
        }
        undoable("Verwijder factuur") {
            data.invoices.removeAll { $0.id == invoice.id }
            // Koppelingen naar deze factuur opruimen
            for i in data.invoices.indices {
                if data.invoices[i].creditedByID == invoice.id { data.invoices[i].creditedByID = nil }
                if data.invoices[i].replacedByID == invoice.id { data.invoices[i].replacedByID = nil }
                if data.invoices[i].creditsInvoiceID == invoice.id { data.invoices[i].creditsInvoiceID = nil }
                if data.invoices[i].replacesInvoiceID == invoice.id { data.invoices[i].replacesInvoiceID = nil }
            }
        }
        show("Factuur \(invoice.number) verwijderd. Ongedaan maken met ⌘Z.")
    }

    func duplicate(_ invoice: Invoice) -> Invoice {
        var copy = makeInvoice(for: client(invoice.clientID))
        copy.archivedFile = nil
        copy.kind = .normal
        copy.kmRate = invoice.kmRate
        copy.lines = invoice.sortedLines.map { var l = $0; l.id = UUID(); return l }
        copy.notes = invoice.notes
        return copy
    }

    func markSent(_ id: UUID) {
        guard let i = data.invoices.firstIndex(where: { $0.id == id }), !data.invoices[i].isSent else { return }
        undoable("Markeer als verstuurd") {
            data.invoices[i].isSent = true
            data.invoices[i].sentDate = Date().startOfDay
            archivePDF(id)
        }
    }

    func addPayment(_ payment: Payment, to id: UUID) {
        guard let i = data.invoices.firstIndex(where: { $0.id == id }) else { return }
        undoable("Registreer betaling") {
            data.invoices[i].payments.append(payment)
            if !data.invoices[i].isSent {
                data.invoices[i].isSent = true
                data.invoices[i].sentDate = data.invoices[i].date
                archivePDF(id)
            }
        }
        show("Betaling van \(payment.amount.euro) geregistreerd bij factuur \(data.invoices[i].number).")
    }

    func markPaid(_ invoice: Invoice, on date: Date = Date()) {
        guard invoice.outstanding > 0 else { return }
        addPayment(Payment(date: date.startOfDay, amount: invoice.outstanding, note: "Volledig betaald"), to: invoice.id)
    }

    func setMemo(_ memo: String, for invoiceID: UUID) {
        guard let i = data.invoices.firstIndex(where: { $0.id == invoiceID }), data.invoices[i].memo != memo else { return }
        undoable("Wijzig opmerking") { data.invoices[i].memo = memo }
    }

    /// Opent de PDF: de gearchiveerde versie als die er is, anders een voorbeeld.
    func openPDF(_ invoice: Invoice) {
        if ProcessInfo.processInfo.environment["MEDIKAS_TEST_CLICKS"] != nil { print("TEST: PDF geopend voor \(invoice.number)"); return }
        if let url = archivedURL(invoice) { NSWorkspace.shared.open(url) }
        else { InvoicePDF.preview(invoice, store: self) }
    }

    func deletePayment(_ paymentID: UUID, from invoiceID: UUID) {
        guard let i = data.invoices.firstIndex(where: { $0.id == invoiceID }) else { return }
        undoable("Verwijder betaling") { data.invoices[i].payments.removeAll { $0.id == paymentID } }
    }

    /// Verstuurde facturen (concepten tellen niet mee in cijfers).
    var sentInvoices: [Invoice] { data.invoices.filter(\.isSent) }
}
