import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Wat we uit een bestaande factuur-PDF kunnen halen om de invoer te versnellen.
/// Alles is een suggestie: de gebruiker controleert en vult zelf aan.
struct ImportedPDFInfo: Equatable {
    var number: String?
    var date: Date?
    var dueDate: Date?
    var total: Decimal?

    static func read(_ url: URL) -> ImportedPDFInfo {
        let text = PDFDocument(url: url)?.string ?? ""
        var info = parse(text)
        if info.number == nil { info.number = numberFromFileName(url.deletingPathExtension().lastPathComponent) }
        return info
    }

    static func parse(_ text: String) -> ImportedPDFInfo {
        var info = ImportedPDFInfo()
        info.number = firstMatch(#"(?i)factuur\s*(?:nummer|nr\.?|no\.?|#)\s*[:#]?\s*([A-Za-z0-9][A-Za-z0-9\-/\.]*[A-Za-z0-9])"#, in: text)
        info.date = firstMatch(#"(?i)factuurdatum\s*:?\s*"# + datePattern, in: text).flatMap(parseDate)
            ?? firstMatch(#"(?i)\bdatum\s*:?\s*"# + datePattern, in: text).flatMap(parseDate)
        info.dueDate = firstMatch(#"(?i)(?:vervaldatum|uiterste betaaldatum|te voldoen v[óo][óo]r)\s*:?\s*"# + datePattern, in: text).flatMap(parseDate)
        // Totaal: het hoogste bedrag op een regel met 'totaal' (niet 'subtotaal').
        let totals = allMatches(#"(?im)^(?!.*subtotaal).*totaal[^\n]*?€?\s*(-?\d{1,3}(?:\.\d{3})*,\d{2}|-?\d+,\d{2})"#, in: text)
            .compactMap(parseAmount)
        info.total = totals.max()
        return info
    }

    private static let datePattern = #"(\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}|\d{1,2}\s+[A-Za-z]+\.?\s+\d{4})"#

    private static func numberFromFileName(_ name: String) -> String? {
        firstMatch(#"(\d{4}[-_]\d{2,4})"#, in: name)?.replacingOccurrences(of: "_", with: "-")
    }

    static func parseDate(_ s: String) -> Date? {
        let clean = s.replacingOccurrences(of: ".", with: s.contains(" ") ? "" : "-")
            .replacingOccurrences(of: "/", with: "-")
        for format in ["d-M-yyyy", "d-M-yy", "d MMMM yyyy", "d MMM yyyy"] {
            let f = DateFormatter()
            f.locale = nl
            f.calendar = nlCalendar
            f.dateFormat = format
            f.isLenient = false
            if let d = f.date(from: clean), (2000...2100).contains(d.year) { return d.startOfDay }
        }
        return nil
    }

    static func parseAmount(_ s: String) -> Decimal? {
        Decimal(string: s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        allMatches(pattern, in: text).first
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
            return ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        }
    }
}

// MARK: - Importeren in de store

extension Store {
    /// Laat een PDF kiezen. Geeft nil terug als de gebruiker annuleert.
    func pickInvoicePDF() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Kies de PDF van de factuur die je buiten MediKas hebt gemaakt."
        panel.prompt = "Importeer"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Start het importeren van een bestaande factuur: kies de PDF en open de editor
    /// met wat er uit de PDF te halen viel.
    func startImport(for client: Client? = nil) {
        guard let url = pickInvoicePDF() else { return }
        editingInvoice = makeImportedInvoice(for: client ?? activeClients.first, pdf: url)
    }

    func makeImportedInvoice(for client: Client?, pdf url: URL) -> Invoice {
        var inv = makeInvoice(for: client)
        let info = ImportedPDFInfo.read(url)
        inv.isImported = true
        inv.isSent = true
        inv.number = info.number.flatMap { isDuplicateNumber($0, id: inv.id) ? nil : $0 } ?? ""
        if let d = info.date {
            inv.date = d
            inv.lines = inv.lines.map { var l = $0; l.date = d; return l }
        }
        inv.dueDate = info.dueDate ?? inv.date.adding(days: data.settings.paymentTermDays)
        inv.sentDate = inv.date
        importSources[inv.id] = ImportSource(url: url, info: info)
        return inv
    }

    /// Kies een andere PDF voor een (nog niet bewaarde of al geïmporteerde) factuur.
    func replaceImportPDF(for id: UUID) -> ImportSource? {
        guard let url = pickInvoicePDF() else { return nil }
        let source = ImportSource(url: url, info: ImportedPDFInfo.read(url))
        importSources[id] = source
        return source
    }

    /// Kopieert de gekozen originele PDF naar het archief, of verplaatst hem als nummer/datum/praktijk
    /// veranderd is. Wordt aangeroepen bij het bewaren van een geïmporteerde factuur.
    func storeImportedPDF(_ id: UUID) {
        guard unavailableReason == nil, let i = data.invoices.firstIndex(where: { $0.id == id }),
              data.invoices[i].isImported else { return }
        let inv = data.invoices[i]
        let rel = archivePath(for: inv)
        let dest = folder.appendingPathComponent(rel)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let source = importSources.removeValue(forKey: id) {
                // Nieuwe PDF gekozen: een eventuele vorige versie blijft bewaard.
                if let existing = archivedURL(inv) {
                    let versions = folder.appendingPathComponent("Facturen/Eerdere versies", isDirectory: true)
                    try? fm.createDirectory(at: versions, withIntermediateDirectories: true)
                    let stamp = DateFormatter.versionStamp.string(from: Date())
                    let name = existing.deletingPathExtension().lastPathComponent + " (vervangen \(stamp)).pdf"
                    try? fm.moveItem(at: existing, to: versions.appendingPathComponent(name))
                }
                let pdf = try Data(contentsOf: source.url)
                try Store.writeCoordinated(pdf, to: dest)
            } else if let existing = archivedURL(inv), existing.standardizedFileURL != dest.standardizedFileURL {
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.moveItem(at: existing, to: dest)
            } else {
                return
            }
            data.invoices[i].archivedFile = rel
        } catch {
            alert = "Originele PDF bewaren mislukt: \(error.localizedDescription)"
        }
    }
}

/// De gekozen originele PDF van een factuur die nog bewaard moet worden.
struct ImportSource: Equatable {
    let url: URL
    let info: ImportedPDFInfo
}
