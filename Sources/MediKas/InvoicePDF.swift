import SwiftUI
import AppKit
import UniformTypeIdentifiers

// A4 in punten
private let pageW: CGFloat = 595.28
private let pageH: CGFloat = 841.89
private let margin: CGFloat = 42
private let rowH: CGFloat = 19
private let ink = Color(white: 0.12)
private let soft = Color(white: 0.42)
private let rule = Color(white: 0.82)

// Kolombreedtes (totaal = pageW - 2*margin ≈ 511)
private enum Work {   // Werkzaamheden
    static let date: CGFloat = 80, desc: CGFloat = 191, hours: CGFloat = 60, rate: CGFloat = 80, amount: CGFloat = 100
}
private enum Travel { // Reiskosten
    static let date: CGFloat = 80, commute: CGFloat = 100, visit: CGFloat = 100, total: CGFloat = 100, amount: CGFloat = 131
}

/// Eén blok op de factuur; de paginering verdeelt deze over pagina's.
enum PDFItem: Hashable {
    case sectionTitle(String)
    case workHeader, work(WorkLine, Int), workTotal
    case travelHeader, travel(WorkLine, Int), travelTotal
    case gap

    var height: CGFloat {
        switch self {
        case .sectionTitle: 24
        case .workHeader, .travelHeader: 22
        case .work, .travel: rowH
        case .workTotal, .travelTotal: 22
        case .gap: 18
        }
    }

    static func items(for invoice: Invoice) -> [PDFItem] {
        let lines = invoice.sortedLines
        var items: [PDFItem] = [.sectionTitle("Werkzaamheden"), .workHeader]
        items += lines.enumerated().map { .work($1, $0) }
        items.append(.workTotal)
        let travel = lines.filter { $0.totalKm != 0 }   // ook negatief (creditfactuur)
        if !travel.isEmpty {
            items += [.gap, .sectionTitle("Reiskosten"), .travelHeader]
            items += travel.enumerated().map { .travel($1, $0) }
            items.append(.travelTotal)
        }
        return items
    }
}

struct InvoicePage: View {
    let invoice: Invoice
    let settings: BusinessSettings
    let logo: NSImage?
    let items: [PDFItem]
    let pageNumber: Int
    let pageCount: Int

    private var isFirst: Bool { pageNumber == 1 }
    private var isLast: Bool { pageNumber == pageCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFirst { header; addressBlock; title } else { continuationHeader }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in itemView(item) }
            if isLast { totals; closing }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, margin)
        .padding(.top, margin)
        .padding(.bottom, 26)
        .frame(width: pageW, height: pageH, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(ink)
        .font(.system(size: 9.5))
        .environment(\.colorScheme, .light)
    }

    // MARK: Kop

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                if let logo {
                    Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
                        .frame(maxWidth: 190, maxHeight: 64, alignment: .leading)
                } else {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6).fill(invoiceAccent).frame(width: 30, height: 30)
                            .overlay(Image(systemName: "stethoscope").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(settings.tradeName.isEmpty ? settings.practiceName : settings.tradeName)
                                .font(.system(size: 19, weight: .bold)).foregroundStyle(invoiceAccent)
                            if !settings.tradeName.isEmpty && settings.practiceName != settings.tradeName {
                                Text(settings.practiceName).font(.system(size: 10)).foregroundStyle(soft)
                            }
                        }
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1.5) {
                if !settings.ownerName.isEmpty { Text(settings.ownerName).fontWeight(.semibold) }
                if !settings.title.isEmpty { Text(settings.title).foregroundStyle(soft) }
                if !settings.address.isEmpty { Text(settings.address) }
                if !(settings.postalCode + settings.city).isEmpty {
                    Text([settings.postalCode, settings.city].filter { !$0.isEmpty }.joined(separator: "  "))
                }
                if !settings.phone.isEmpty { Text(settings.phone) }
                if !settings.email.isEmpty { Text(settings.email) }
                if !settings.website.isEmpty { Text(settings.website) }
            }
            .font(.system(size: 9))
        }
        .padding(.bottom, 26)
    }

    private var addressBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FACTUUR AAN").font(.system(size: 7.5, weight: .semibold)).kerning(0.8).foregroundStyle(soft).padding(.bottom, 2)
                Text(invoice.billTo.displayName).font(.system(size: 11, weight: .semibold))
                if !invoice.billTo.contactPerson.isEmpty { Text("t.a.v. \(invoice.billTo.contactPerson)") }
                if !invoice.billTo.address.isEmpty { Text(invoice.billTo.address) }
                if !(invoice.billTo.postalCode + invoice.billTo.city).isEmpty {
                    Text([invoice.billTo.postalCode, invoice.billTo.city].filter { !$0.isEmpty }.joined(separator: "  "))
                }
            }
            Spacer()
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                meta(invoice.isCredit ? "Creditnummer" : "Factuurnummer", invoice.number, bold: true)
                meta("Datum", invoice.date.long)
                if !invoice.isCredit { meta("Vervaldatum", invoice.dueDate.long) }
                if !invoice.relatedNumber.isEmpty {
                    meta(invoice.isCredit ? "Crediteert factuur" : "Vervangt factuur",
                         invoice.relatedNumber + (invoice.relatedDate.map { " van \($0.long)" } ?? ""), bold: true)
                }
                if !invoice.periodText.isEmpty { meta("Periode", invoice.periodText) }
            }
        }
        .padding(.bottom, 20)
    }

    private var title: some View {
        Text(invoice.documentTitle).font(.system(size: 22, weight: .bold)).foregroundStyle(invoiceAccent)
            .padding(.bottom, 12)
    }

    private func meta(_ label: String, _ value: String, bold: Bool = false) -> some View {
        GridRow {
            Text(label).foregroundStyle(soft)
            Text(value).fontWeight(bold ? .semibold : .regular)
        }
    }

    private var continuationHeader: some View {
        HStack {
            Text(settings.tradeName.isEmpty ? settings.practiceName : settings.tradeName)
                .font(.system(size: 12, weight: .bold)).foregroundStyle(invoiceAccent)
            Spacer()
            Text("\(invoice.documentTitle) \(invoice.number) — vervolg").foregroundStyle(soft)
        }
        .padding(.bottom, 18)
    }

    // MARK: Tabellen

    private var kmRateText: String {
        invoice.kmRate.formatted(.currency(code: "EUR").precision(.fractionLength(2...3)).locale(nl))
    }

    @ViewBuilder private func itemView(_ item: PDFItem) -> some View {
        switch item {
        case .sectionTitle(let title):
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(invoiceAccent)
                .frame(height: 24, alignment: .bottomLeading).padding(.bottom, 0)
        case .gap:
            Color.clear.frame(height: 18)

        case .workHeader:
            headerRow {
                cell("Datum", Work.date, .leading); cell("Omschrijving", Work.desc, .leading)
                cell("Uren", Work.hours); cell("Uurtarief", Work.rate); cell("Bedrag", Work.amount)
            }
        case .work(let line, let i):
            HStack(spacing: 0) {
                cell(line.date.short, Work.date, .leading)
                cell(line.description, Work.desc, .leading)
                cell(line.hours.fmt(), Work.hours)
                cell(line.hourlyRate.euro, Work.rate)
                cell(line.hoursAmount.euro, Work.amount)
            }
            .frame(height: rowH)
            .background(i.isMultiple(of: 2) ? Color.clear : Color(white: 0.965))
        case .workTotal:
            totalRow {
                cell("Subtotaal", Work.date + Work.desc, .leading)
                cell(invoice.hours.fmt(), Work.hours); cell("", Work.rate)
                cell(invoice.hoursAmount.euro, Work.amount)
            }

        case .travelHeader:
            headerRow {
                cell("Datum", Travel.date, .leading); cell("Woon-werk km", Travel.commute)
                cell("Visites km", Travel.visit); cell("Totaal km", Travel.total)
                cell("Bedrag (\(kmRateText)/km)", Travel.amount)
            }
        case .travel(let line, let i):
            HStack(spacing: 0) {
                cell(line.date.short, Travel.date, .leading)
                cell(line.commuteKm == 0 ? "–" : line.commuteKm.fmt(1), Travel.commute)
                cell(line.visitKm == 0 ? "–" : line.visitKm.fmt(1), Travel.visit)
                cell(line.totalKm.fmt(1), Travel.total)
                cell((line.totalKm * invoice.kmRate).rounded().euro, Travel.amount)
            }
            .frame(height: rowH)
            .background(i.isMultiple(of: 2) ? Color.clear : Color(white: 0.965))
        case .travelTotal:
            totalRow {
                cell("Subtotaal", Travel.date, .leading)
                cell(invoice.commuteKm.fmt(1), Travel.commute)
                cell(invoice.visitKm.fmt(1), Travel.visit)
                cell(invoice.totalKm.fmt(1), Travel.total)
                cell(invoice.kmAmount.euro, Travel.amount)
            }
        }
    }

    private func headerRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 0, content: content)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white)
            .frame(height: 22)
            .background(invoiceAccent)
    }

    private func totalRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 0, content: content)
            .fontWeight(.semibold)
            .frame(height: 22)
            .overlay(alignment: .top) { Rectangle().fill(rule).frame(height: 0.7) }
            .monospacedDigit()
    }

    private func cell(_ text: String, _ width: CGFloat, _ align: Alignment = .trailing) -> some View {
        Text(text).lineLimit(1).truncationMode(.tail)
            .padding(.horizontal, 4)
            .frame(width: width, alignment: align)
            .monospacedDigit()
    }

    // MARK: Totalen

    private var totals: some View {
        HStack {
            Spacer()
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 5) {
                GridRow {
                    Text("Werkzaamheden (\(invoice.hours.fmt()) uur)").gridColumnAlignment(.leading)
                    Text(invoice.hoursAmount.euro)
                }
                if invoice.totalKm != 0 {
                    GridRow {
                        Text("Reiskosten (\(invoice.totalKm.fmt(1)) km × \(kmRateText))")
                        Text(invoice.kmAmount.euro)
                    }
                }
                GridRow {
                    Rectangle().fill(ink).frame(height: 0.8).gridCellColumns(2)
                }
                GridRow {
                    Text(invoice.isCredit ? "Totaal creditbedrag" : "Totaal te betalen").font(.system(size: 11.5, weight: .bold))
                    Text(invoice.total.euro).font(.system(size: 11.5, weight: .bold)).foregroundStyle(invoiceAccent)
                }
                if !settings.vatText.isEmpty {
                    GridRow {
                        Text(settings.vatText).font(.system(size: 7.5)).italic().foregroundStyle(soft)
                            .gridCellColumns(2).gridCellAnchor(.trailing)
                    }
                }
            }
            .frame(width: 300)
            .monospacedDigit()
        }
        .padding(.top, 18)
    }

    private var closing: some View {
        VStack(alignment: .leading, spacing: 8) {
            if invoice.isCredit {
                Text("Deze creditfactuur crediteert factuur \(invoice.relatedNumber)\(invoice.relatedDate.map { " van \($0.long)" } ?? "") volledig. U hoeft niets te betalen; een eventueel al betaald bedrag wordt verrekend of teruggestort.")
            } else if !invoice.relatedNumber.isEmpty {
                Text("Deze factuur vervangt factuur \(invoice.relatedNumber)\(invoice.relatedDate.map { " van \($0.long)" } ?? ""), die met een creditfactuur is gecrediteerd.")
            }
            if !invoice.notes.isEmpty { Text(invoice.notes) }
            if !invoice.isCredit { Text(paymentSentence) }
            if !settings.closingText.isEmpty { Text(settings.closingText) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 26)
    }

    private var paymentSentence: String {
        settings.paymentText
            .replacingOccurrences(of: "{TERMIJN}", with: "\(settings.paymentTermDays)")
            .replacingOccurrences(of: "{IBAN}", with: settings.iban.isEmpty ? "ons rekeningnummer" : settings.iban)
            .replacingOccurrences(of: "{NAAM}", with: settings.holder)
            .replacingOccurrences(of: "{FACTUUR}", with: invoice.number)
            .replacingOccurrences(of: "{BEDRAG}", with: invoice.total.euro)
            .replacingOccurrences(of: "{VERVALDATUM}", with: invoice.dueDate.long)
    }

    // MARK: Voet

    private var footer: some View {
        VStack(spacing: 4) {
            Rectangle().fill(rule).frame(height: 0.7)
            HStack {
                Text(footerItems.joined(separator: "   ·   "))
                Spacer()
                if pageCount > 1 { Text("Pagina \(pageNumber) van \(pageCount)") }
            }
            .font(.system(size: 7.5))
            .foregroundStyle(soft)
        }
    }

    private var footerItems: [String] {
        var items = [settings.practiceName]
        if !settings.kvk.isEmpty { items.append("KvK \(settings.kvk)") }
        if !settings.agb.isEmpty { items.append("AGB \(settings.agb)") }
        if !settings.big.isEmpty { items.append("BIG \(settings.big)") }
        if !settings.vatNumber.isEmpty { items.append("Btw-id \(settings.vatNumber)") }
        if !settings.iban.isEmpty { items.append("IBAN \(settings.iban)\(settings.bic.isEmpty ? "" : " (\(settings.bic))")") }
        return items
    }
}

// MARK: - PDF maken, bewaren en mailen

@MainActor
enum InvoicePDF {
    /// Verdeelt de blokken over pagina's op basis van hoogte. Een tabel die doorloopt krijgt
    /// op de volgende pagina opnieuw zijn kop; de laatste pagina heeft ruimte voor totalen.
    static func paginate(_ items: [PDFItem]) -> [[PDFItem]] {
        let firstCap: CGFloat = 520, nextCap: CGFloat = 700, totalsHeight: CGFloat = 205
        var pages: [[PDFItem]] = [[]]
        var used: CGFloat = 0
        func cap() -> CGFloat { pages.count == 1 ? firstCap : nextCap }

        for item in items {
            var needed = item.height
            // Een sectietitel niet los onderaan een pagina: houd hem bij kop + eerste regel.
            if case .sectionTitle = item { needed += 22 + rowH }
            if used + needed > cap() && !(pages.last ?? []).isEmpty {
                pages.append([]); used = 0
                if case .gap = item { continue }
                switch item {
                case .work, .workTotal: pages[pages.count - 1].append(.workHeader); used += 22
                case .travel, .travelTotal: pages[pages.count - 1].append(.travelHeader); used += 22
                default: break
                }
            }
            pages[pages.count - 1].append(item)
            used += item.height
        }
        if used + totalsHeight > cap() { pages.append([]) }
        return pages
    }

    static func pages(for invoice: Invoice, settings: BusinessSettings, logo: NSImage?) -> [InvoicePage] {
        let chunks = paginate(PDFItem.items(for: invoice))
        return chunks.enumerated().map { i, items in
            InvoicePage(invoice: invoice, settings: settings, logo: logo,
                        items: items, pageNumber: i + 1, pageCount: chunks.count)
        }
    }

    static func data(for invoice: Invoice, store: Store) -> Data? {
        data(for: invoice, settings: store.data.settings, logo: store.logo)
    }

    static func data(for invoice: Invoice, settings: BusinessSettings, logo: NSImage?) -> Data? {
        let out = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let consumer = CGDataConsumer(data: out as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, [
                kCGPDFContextTitle: "Factuur \(invoice.number)",
                kCGPDFContextAuthor: settings.practiceName,
                kCGPDFContextCreator: "MediKas",
              ] as CFDictionary) else { return nil }
        for page in pages(for: invoice, settings: settings, logo: logo) {
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(width: pageW, height: pageH)
            renderer.render { _, draw in
                ctx.beginPDFPage(nil)
                draw(ctx)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return out as Data
    }

    static func fileName(_ invoice: Invoice) -> String {
        let client = invoice.billTo.displayName.replacingOccurrences(of: "/", with: "-")
        return "\(invoice.documentTitle) \(invoice.number) - \(client).pdf"
    }

    private static func writeTemp(_ invoice: Invoice, store: Store) -> URL? {
        guard let data = data(for: invoice, store: store) else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MediKas", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName(invoice))
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    /// Opent de PDF in Voorvertoning zonder iets te bewaren.
    static func preview(_ invoice: Invoice, store: Store) {
        guard let url = writeTemp(invoice, store: store) else { return }
        NSWorkspace.shared.open(url)
    }

    static func export(_ invoice: Invoice, store: Store) {
        guard let data = data(for: invoice, store: store) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName(invoice)
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            store.markSent(invoice.id)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            store.alert = "PDF bewaren mislukt: \(error.localizedDescription)"
        }
    }

    static func mail(_ invoice: Invoice, store: Store) {
        guard let url = writeTemp(invoice, store: store),
              let service = NSSharingService(named: .composeEmail) else { return }
        // Bij een vervangende factuur hoort de creditfactuur van de oude factuur er ook bij
        let original = store.invoice(invoice.replacesInvoiceID)
        let credit = store.invoice(original?.creditedByID)
        let creditURL = credit.flatMap { writeTemp($0, store: store) }
        let s = store.data.settings
        if !invoice.billTo.email.isEmpty { service.recipients = [invoice.billTo.email] }
        service.subject = "Factuur \(invoice.number) – \(s.displayName)"
        let greeting = invoice.billTo.contactPerson.isEmpty ? "Beste collega's," : "Beste \(invoice.billTo.contactPerson),"
        let intro: String
        if invoice.isCredit {
            service.subject = "Creditfactuur \(invoice.number) – \(s.displayName)"
            intro = "Hierbij stuur ik creditfactuur \(invoice.number), waarmee factuur \(invoice.relatedNumber) volledig wordt gecrediteerd. U hoeft hiervoor niets te betalen."
        } else if let original, let credit, creditURL != nil {
            intro = "Factuur \(original.number) bevatte een fout. Daarom stuur ik creditfactuur \(credit.number), die factuur \(original.number) ongedaan maakt, en de gecorrigeerde factuur \(invoice.number). Het totaalbedrag van de nieuwe factuur is \(invoice.total.euro), te voldoen vóór \(invoice.dueDate.long). Excuses voor het ongemak."
        } else {
            intro = "Hierbij stuur ik de factuur \(invoice.number) voor de waarneming\(invoice.periodText.isEmpty ? "" : " (\(invoice.periodText))"). Het totaalbedrag is \(invoice.total.euro), te voldoen vóór \(invoice.dueDate.long)."
        }
        let body = """
        \(greeting)

        \(intro)

        Met vriendelijke groet,

        \(s.ownerName.isEmpty ? s.practiceName : s.ownerName)
        \(s.tradeName.isEmpty ? "" : s.tradeName)
        """
        service.perform(withItems: [body] + [creditURL, url].compactMap { $0 })
        if let credit, creditURL != nil { store.markSent(credit.id) }
        store.markSent(invoice.id)
    }
}
