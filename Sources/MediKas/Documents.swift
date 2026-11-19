import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Documenten per praktijk (bv. contracten), als gewone bestanden in de gegevensmap:
//   <gegevensmap>/Waarnemingsovereenkomsten/<praktijknaam>/<bestand>
// De map is de bron: bestanden die je zelf in de Finder neerzet, verschijnen ook in MediKas.

extension Store {
    static let documentsFolderName = "Waarnemingsovereenkomsten"

    var documentsRoot: URL { folder.appendingPathComponent(Store.documentsFolderName, isDirectory: true) }

    /// Mapnaam voor een praktijknaam: zonder tekens die in een bestandsnaam niet mogen.
    static func safeFolderName(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        return s
    }

    /// De documentenmap van een praktijk; nil zolang de praktijk geen naam heeft.
    func documentsFolder(for client: Client) -> URL? {
        let name = client.documentsFolder.isEmpty ? Store.safeFolderName(client.name) : client.documentsFolder
        return name.isEmpty ? nil : documentsRoot.appendingPathComponent(name, isDirectory: true)
    }

    /// De bestanden in de documentenmap, nieuwste eerst.
    func documents(for client: Client) -> [URL] {
        guard let dir = documentsFolder(for: client) else { return [] }
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.modificationDate > $1.modificationDate }
    }

    /// Kopieert bestanden naar de map van de praktijk. Bestaat de naam al, dan komt er " (2)" achter.
    func addDocuments(_ urls: [URL], to clientID: UUID) {
        guard unavailableReason == nil, let client = client(clientID) else { return }
        syncDocumentsFolder(clientID)
        guard let dir = documentsFolder(for: client) else {
            alert = "Geef de praktijk eerst een naam; die wordt de naam van de map."
            return
        }
        let fm = FileManager.default
        var added = 0
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for url in urls where !Store.isDirectory(url) {
                let dest = Store.uniqueURL(dir.appendingPathComponent(url.lastPathComponent))
                try fm.copyItem(at: url, to: dest)
                added += 1
            }
        } catch {
            alert = "Document toevoegen mislukt: \(error.localizedDescription)"
        }
        if let i = data.clients.firstIndex(where: { $0.id == clientID }), data.clients[i].documentsFolder.isEmpty {
            data.clients[i].documentsFolder = dir.lastPathComponent
        }
        if added > 0 { show(added == 1 ? "Document toegevoegd." : "\(added) documenten toegevoegd.") }
    }

    /// Verplaatst een document naar de prullenmand (terug te halen in de Finder).
    func trashDocument(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            show("\(url.lastPathComponent) staat in de prullenmand.")
        } catch {
            alert = "Verwijderen mislukt: \(error.localizedDescription)"
        }
    }

    /// Laat de map de naam van de praktijk volgen (na hernoemen).
    func syncDocumentsFolder(_ clientID: UUID) {
        guard unavailableReason == nil, let i = data.clients.firstIndex(where: { $0.id == clientID }) else { return }
        let old = data.clients[i].documentsFolder
        let new = Store.safeFolderName(data.clients[i].name)
        guard !old.isEmpty, !new.isEmpty, old != new else { return }
        let fm = FileManager.default
        let from = documentsRoot.appendingPathComponent(old, isDirectory: true)
        let to = documentsRoot.appendingPathComponent(new, isDirectory: true)
        if Store.isDirectory(from) {
            if !fm.fileExists(atPath: to.path) {
                // Alleen hoofdletters anders (APFS is niet hoofdlettergevoelig): via een tijdelijke naam.
                if old.lowercased() == new.lowercased() {
                    let tmp = documentsRoot.appendingPathComponent(".hernoemen-\(UUID().uuidString)")
                    guard (try? fm.moveItem(at: from, to: tmp)) != nil, (try? fm.moveItem(at: tmp, to: to)) != nil else { return }
                } else {
                    guard (try? fm.moveItem(at: from, to: to)) != nil else { return }
                }
            } else {
                // Er is al een map met de nieuwe naam: bestanden erbij zetten.
                let files = (try? fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil)) ?? []
                for f in files { try? fm.moveItem(at: f, to: Store.uniqueURL(to.appendingPathComponent(f.lastPathComponent))) }
                if ((try? fm.contentsOfDirectory(atPath: from.path)) ?? []).filter({ $0 != ".DS_Store" }).isEmpty {
                    try? fm.removeItem(at: from)
                }
            }
        }
        data.clients[i].documentsFolder = new
    }

    static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        for n in 2... {
            let candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }
}

private extension URL {
    var modificationDate: Date { (try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
    var fileSize: Int { (try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
}

// MARK: - Kaart op de praktijkpagina

struct DocumentsCard: View {
    @EnvironmentObject var store: Store
    let clientID: UUID
    @Local private var files: [URL] = []
    @Local private var dropTargeted = false

    private var client: Client { store.client(clientID) ?? Client() }
    private var folder: URL? { store.documentsFolder(for: client) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "folder", title: "Documenten",
                       subtitle: "Bijv. waarnemingsovereenkomsten · \(Store.documentsFolderName) › \(folder?.lastPathComponent ?? "praktijknaam")") {
                HStack(spacing: 8) {
                    if let folder, Store.isDirectory(folder) {
                        Button { NSWorkspace.shared.open(folder) } label: {
                            Label("Toon map", systemImage: "folder").labelStyle(.titleAndIcon)
                        }
                        .help("Open de map van deze praktijk in de Finder")
                    }
                    Button { pickFiles() } label: {
                        Label("Voeg toe…", systemImage: "plus").labelStyle(.titleAndIcon)
                    }
                    .help("Voeg een of meer documenten toe (je kunt ze ook hierheen slepen)")
                    .disabled(folder == nil)
                }
            }

            if files.isEmpty {
                EmptyState(icon: "doc.on.doc", title: "Nog geen documenten",
                           message: folder == nil ? "Geef de praktijk eerst een naam."
                                                  : "Sleep bijvoorbeeld een contract hierheen, of kies ‘Voeg toe…’.",
                           primary: folder == nil ? nil : ("Voeg toe…", { pickFiles() }), compact: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(files, id: \.self) { url in DocumentRow(url: url, onTrash: { trash(url) }) }
                }
            }
        }
        .card(padding: 18)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard folder != nil else { return false }
            store.addDocuments(urls.filter(\.isFileURL), to: clientID)
            reload()
            return true
        } isTargeted: { dropTargeted = $0 && folder != nil }
        .onAppear { store.syncDocumentsFolder(clientID); reload() }
        // Naam gewijzigd: even wachten tot het typen klaar is, dan de map meenemen.
        .task(id: client.name) {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            store.syncDocumentsFolder(clientID)
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
    }

    private func reload() { files = store.documents(for: client) }

    private func trash(_ url: URL) {
        store.trashDocument(url)
        reload()
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Voeg toe"
        panel.message = "Kies de documenten voor \(client.displayName)"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        store.addDocuments(panel.urls, to: clientID)
        reload()
    }
}

struct DocumentRow: View {
    let url: URL
    let onTrash: () -> Void
    @Local private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 24, height: 24).accessibilityHidden(true)
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ByteCountFormatter.string(fromByteCount: Int64(url.fileSize), countStyle: .file))
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            Text(url.modificationDate.long)
                .font(.callout).foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis").frame(width: 18, height: 16)
            }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.borderless).fixedSize()
            .opacity(hovering ? 1 : 0.4)
            .accessibilityLabel("Acties voor \(url.lastPathComponent)")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(hovering ? Color.well : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu { actions }
        .draggable(url)   // naar Mail of de Finder slepen
        .help("Dubbelklik om te openen")
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Open") { NSWorkspace.shared.open(url) }
    }

    @ViewBuilder private var actions: some View {
        Button("Open") { NSWorkspace.shared.open(url) }
        Button("Toon in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Divider()
        Button("Verplaats naar prullenmand", role: .destructive, action: onTrash)
    }
}
